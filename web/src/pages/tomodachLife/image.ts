import { rgbToTomodachiHSV, tomodachiHSVToRgb, type RGBColor } from "./color";

/// Image ByteArray Struct:
///    width         height      colorSize        Colors            pixels
///     u16           u16           u8        3*u8*colorSize     width*height*u8
/// image width   image height   olor size   HSV colors array    0 means empty pixel, else is corlor index of color array      

/// Image Struct
export interface Image {
  width: number,
  height: number,
  palette: RGBColor[],
  pIndices: (number | null)[][]
}

export const generateZigByteArray = (
  {
    width,
    height,
    palette,
    pIndices,
  }: Image
): Uint8Array => {
  const w = width;
  const h = height;

  const colorSize = palette.length + 1;
  const headerSize = 5;
  const colorTableSize = palette.length * 3;
  const pixelTableSize = w * h;

  const buffer = new Uint8Array(headerSize + colorTableSize + pixelTableSize);

  buffer[0] = w & 0xff;
  buffer[1] = (w >> 8) & 0xff;
  buffer[2] = h & 0xff;
  buffer[3] = (h >> 8) & 0xff;
  buffer[4] = colorSize;

  palette.forEach((color, i) => {
    const hsv = rgbToTomodachiHSV(color.r, color.g, color.b);
    const offset = 5 + i * 3;
    buffer[offset] = hsv.hTicks;
    buffer[offset + 1] = hsv.sTicks;
    buffer[offset + 2] = hsv.vTicks;
  });

  const pixelStartOffset = 5 + palette.length * 3;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const idx = y * w + x;
      const colorIdx = pIndices[y]?.[x];
      buffer[pixelStartOffset + idx] = colorIdx !== undefined && colorIdx !== null ? colorIdx + 1 : 0;
    }
  }

  return buffer;
};

export const loadImageFromZigByteArray = (buffer: Uint8Array): Image | null => {
  if (buffer.length < 5) return null;
  
  const w = buffer[0] | (buffer[1] << 8);
  const h = buffer[2] | (buffer[3] << 8);
  const colorSize = buffer[4];
  const paletteLength = Math.max(0, colorSize - 1);

  // 读取调色板 (每个颜色 3 字节)
  const palette: RGBColor[] = [];
  for (let i = 0; i < paletteLength; i++) {
    const offset = 5 + i * 3;
    if (offset + 2 < buffer.length) {
      const hTicks = buffer[offset];
      const sTicks = buffer[offset + 1];
      const vTicks = buffer[offset + 2];
      palette.push(tomodachiHSVToRgb(hTicks, sTicks, vTicks));
    }
  }

  // 计算像素起始偏移量 (适配兼容性)
  let pixelStartOffset = 5 + paletteLength * 3;
  if (pixelStartOffset + w * h > buffer.length && 5 + colorSize * 3 + w * h <= buffer.length) {
    pixelStartOffset = 5 + colorSize * 3;
  }

  // 读取像素矩阵
  const pIndices: (number | null)[][] = [];
  for (let y = 0; y < h; y++) {
    const row: (number | null)[] = [];
    for (let x = 0; x < w; x++) {
      const idx = pixelStartOffset + y * w + x;
      const val = idx < buffer.length ? buffer[idx] : 0;
      row.push(val > 0 ? val - 1 : null);
    }
    pIndices.push(row);
  }

  return {
    width: w,
    height: h,
    palette,
    pIndices
  };
};