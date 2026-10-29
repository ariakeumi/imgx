//! C ABI over the minifier core, consumed by the native macOS app.
//!
//! The boundary is deliberately thin: bytes in, bytes plus a small JSON
//! metadata block out. File caching, hashing and concurrency limits all live
//! on the Swift side; `optimize_image` itself is a pure function.

use std::cell::RefCell;
use std::ffi::{c_char, CStr, CString};
use std::ptr;

use imgo_shared::types::{ImageFormat, OptimizeOptions};
use minifier::OptimizeResult;

#[repr(C)]
pub struct ImgoResult {
  pub data: *mut u8,
  pub len: usize,
  pub meta_json: *mut c_char,
}

thread_local! {
  static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

fn set_last_error(message: impl Into<String>) {
  let message = message.into();
  LAST_ERROR.with(|slot| {
    slot.borrow_mut().replace(
      CString::new(message)
        .unwrap_or_else(|_| CString::new("error message contains NUL byte").unwrap()),
    );
  });
}

#[derive(Default, serde::Deserialize)]
struct Request {
  output_format: Option<ImageFormat>,
  #[serde(default)]
  options: Option<OptimizeOptions>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct ResultMeta {
  format: ImageFormat,
  width: u32,
  height: u32,
  input_width: u32,
  input_height: u32,
}

impl From<&OptimizeResult> for ResultMeta {
  fn from(result: &OptimizeResult) -> Self {
    Self {
      format: result.output_type,
      width: result.output_resolution.width,
      height: result.output_resolution.height,
      input_width: result.input_resolution.width,
      input_height: result.input_resolution.height,
    }
  }
}

const ERR_INVALID_ARGS: i32 = 1;
const ERR_OPTIMIZE_FAILED: i32 = 3;

/// # Safety
/// `input` must point to `input_len` readable bytes, `request_json` must be a
/// NUL-terminated UTF-8 string or NULL, and `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn imgo_optimize(
  input: *const u8,
  input_len: usize,
  request_json: *const c_char,
  out: *mut ImgoResult,
) -> i32 {
  if input.is_null() || out.is_null() {
    set_last_error("input and out pointers must not be NULL");
    return ERR_INVALID_ARGS;
  }

  let request = if request_json.is_null() {
    Request::default()
  } else {
    let raw = CStr::from_ptr(request_json);
    let Ok(json) = raw.to_str() else {
      set_last_error("request_json is not valid UTF-8");
      return ERR_INVALID_ARGS;
    };
    match serde_json::from_str::<Request>(json) {
      Ok(request) => request,
      Err(err) => {
        set_last_error(format!("invalid request json: {err}"));
        return ERR_INVALID_ARGS;
      }
    }
  };

  let buffer = std::slice::from_raw_parts(input, input_len);

  let run = || {
    minifier::optimize_image(
      buffer,
      request.output_format,
      request.options.clone(),
      None,
    )
  };
  // `optimize_image` returns `anyhow::Result`; panics inside encoders are
  // already surfaced as errors there, but keep the barrier defensive anyway.
  let result = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(run)) {
    Ok(Ok(result)) => result,
    Ok(Err(err)) => {
      set_last_error(format!("{err:#}"));
      return ERR_OPTIMIZE_FAILED;
    }
    Err(panic) => {
      let message = panic
        .downcast_ref::<&str>()
        .map(|s| s.to_string())
        .or_else(|| panic.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "encoder panicked".to_string());
      set_last_error(format!("encoder panicked: {message}"));
      return ERR_OPTIMIZE_FAILED;
    }
  };

  let meta_json = match serde_json::to_string(&ResultMeta::from(&result)) {
    Ok(json) => json,
    Err(err) => {
      set_last_error(format!(
        "failed to serialize result metadata: {err}"
      ));
      return ERR_OPTIMIZE_FAILED;
    }
  };
  let Ok(meta_json) = CString::new(meta_json) else {
    set_last_error("result metadata contains NUL byte");
    return ERR_OPTIMIZE_FAILED;
  };

  let mut data = result.data;
  let len = data.len();
  let data_ptr = data.as_mut_ptr();
  std::mem::forget(data);

  *out = ImgoResult {
    data: data_ptr,
    len,
    meta_json: meta_json.into_raw(),
  };
  0
}

/// # Safety
/// `result` must be NULL or point to an `ImgoResult` filled by `imgo_optimize`
/// and not yet freed.
#[no_mangle]
pub unsafe extern "C" fn imgo_result_free(result: *mut ImgoResult) {
  if result.is_null() {
    return;
  }

  let owned = ptr::read(result);
  if !owned.data.is_null() {
    drop(Vec::from_raw_parts(
      owned.data, owned.len, owned.len,
    ));
  }
  if !owned.meta_json.is_null() {
    drop(CString::from_raw(owned.meta_json));
  }
}

/// # Safety
/// The returned pointer is only guaranteed to be valid until the next failing
/// `imgo_*` call on the same thread. Calling code must not free or mutate it.
#[no_mangle]
pub extern "C" fn imgo_last_error() -> *const c_char {
  LAST_ERROR.with(|slot| match slot.borrow().as_ref() {
    Some(message) => message.as_ptr(),
    None => ptr::null(),
  })
}

#[cfg(test)]
mod tests {
  use super::*;
  use std::ffi::CString;

  fn sample_jpeg() -> &'static [u8] {
    include_bytes!("../../minifier/samples/jpeg/sample.jpg")
  }

  unsafe fn call_optimize(input: &[u8], request_json: Option<&str>) -> (i32, Option<ImgoResult>) {
    // Keep the CString alive for the duration of the call.
    let request_cstring = request_json.map(|json| CString::new(json).unwrap());
    let request_ptr = request_cstring
      .as_ref()
      .map_or(std::ptr::null(), |cstring| {
        cstring.as_ptr()
      });

    let mut result = ImgoResult {
      data: ptr::null_mut(),
      len: 0,
      meta_json: ptr::null_mut(),
    };

    let status = imgo_optimize(
      input.as_ptr(),
      input.len(),
      request_ptr,
      &mut result,
    );
    if status == 0 {
      (status, Some(result))
    } else {
      (status, None)
    }
  }

  unsafe fn last_error_string() -> String {
    let error = imgo_last_error();
    assert!(
      !error.is_null(),
      "expected an error message"
    );
    CStr::from_ptr(error).to_string_lossy().into_owned()
  }

  #[test]
  fn optimizes_jpeg_with_defaults() {
    unsafe {
      let (status, result) = call_optimize(sample_jpeg(), None);
      assert_eq!(status, 0, "{}", last_error_string());

      let result = result.unwrap();
      let bytes = std::slice::from_raw_parts(result.data, result.len);
      // Output keeps the input format: JPEG magic SOI.
      assert_eq!(&bytes[0..2], &[0xFF, 0xD8]);

      let meta = CStr::from_ptr(result.meta_json).to_string_lossy();
      assert!(
        meta.contains("\"format\":\"JPEG\""),
        "meta was {meta}"
      );
      assert!(meta.contains("\"inputWidth\""));

      imgo_result_free(&result as *const ImgoResult as *mut ImgoResult);
    }
  }

  #[test]
  fn converts_jpeg_to_webp() {
    unsafe {
      let (status, result) = call_optimize(
        sample_jpeg(),
        Some(r#"{"output_format":"WEBP"}"#),
      );
      assert_eq!(status, 0, "{}", last_error_string());

      let result = result.unwrap();
      let bytes = std::slice::from_raw_parts(result.data, result.len);
      // RIFF....WEBP container header.
      assert_eq!(&bytes[0..4], b"RIFF");
      assert_eq!(&bytes[8..12], b"WEBP");

      imgo_result_free(&result as *const ImgoResult as *mut ImgoResult);
    }
  }

  #[test]
  fn rejects_invalid_request_json() {
    unsafe {
      let (status, _) = call_optimize(sample_jpeg(), Some("{not json"));
      assert_eq!(status, ERR_INVALID_ARGS);
      assert!(last_error_string().contains("invalid request json"));
    }
  }

  #[test]
  fn rejects_unknown_input_format() {
    unsafe {
      let (status, _) = call_optimize(b"definitely not an image", None);
      assert_eq!(status, ERR_OPTIMIZE_FAILED);
      assert!(last_error_string().contains("Unknown image format"));
    }
  }

  #[test]
  fn freeing_null_is_a_noop() {
    unsafe {
      imgo_result_free(std::ptr::null_mut());
    }
  }
}
