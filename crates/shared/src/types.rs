use serde::{Deserialize, Serialize};

fn default_quality() -> u8 {
  85
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash, Deserialize, Serialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum ImageFormat {
  Png = 1,
  Jpeg = 2,
  Gif = 3,
  WebP = 4,
  Pnm = 5,
  Tiff = 6,
  Tga = 7,
  Dds = 8,
  Bmp = 9,
  Ico = 10,
  Hdr = 11,
  OpenExr = 12,
  Farbfeld = 13,
  Avif = 14,
  Qoi = 15,
  // image::ImageFormat doesn't support these formats:
  Heic = 16,
  Jxl = 17,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Size {
  pub width: u32,
  pub height: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ResizeType {
  Exact = 0,
  DownsizeContain = 1,
  DownsizeCover = 2,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ImageResolution {
  pub width: u32,
  pub height: u32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ResizeOptions {
  pub width: u32,
  pub height: u32,
  pub r#type: ResizeType,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct OptimizeOptions {
  /// use indexed color, png only
  pub indexed: Option<bool>,
  #[serde(default = "default_quality")]
  pub quality: u8,
  pub lossless: Option<bool>,
  pub preserve_metadata: Option<bool>,
  pub resize: Option<ResizeOptions>,
  pub speed: Option<u8>,
  pub fastest: Option<bool>,
}
