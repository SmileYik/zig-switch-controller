import React, { useState, useRef, useMemo } from 'react';
import './TomodachiLifeNormal.css';
import { hexToRgb, rgbToHex, rgbToTomodachiHSV, tomodachiHSVToRgb, type PixelData, type RGBColor } from './color';
import { generateZigMacroScriptBySegment } from './macroAlgorithm';

interface TomodachiLifeNormalProps {
  onChangeScript: (value: string) => void;
}

function TomodachiLifeNormal({
  onChangeScript
}: TomodachiLifeNormalProps) {
  const [cropWidth, setCropWidth] = useState<number>(256);
  const [cropHeight, setCropHeight] = useState<number>(256);
  const [delayMs, setDelayMs] = useState<number>(80);

  const [originalImage, setOriginalImage] = useState<HTMLImageElement | null>(null);
  const [croppedImage, setCroppedImage] = useState<HTMLImageElement | null>(null);
  const [pixelIndices, setPixelIndices] = useState<(number | null)[][]>([]);

  const [originalPalette, setOriginalPalette] = useState<RGBColor[]>([]);
  const [currentPalette, setCurrentPalette] = useState<RGBColor[]>([]);
  const [editingIndex, setEditingIndex] = useState<number | null>(null);

  const [byteArray, setByteArray] = useState<Uint8Array | null>(null);

  const [colorCount, setColorCount] = useState<number>(4);

  const [isCropping, setIsCropping] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);

  const [scale, setScale] = useState<number>(1);
  const [minScale, setMinScale] = useState<number>(0.1);
  const [maxScale, setMaxScale] = useState<number>(10);
  const [imgOffset, setImgOffset] = useState({ x: 0, y: 0 });
  const [isDragging, setIsDragging] = useState(false);
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });

  const fileInputRef = useRef<HTMLInputElement>(null);

  const quantizePixels = (rawPixels: PixelData[][], k: number, w: number, h: number) => {
    const validPixels: RGBColor[] = [];
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        if (rawPixels[y][x]) validPixels.push(rawPixels[y][x]!);
      }
    }

    const emptyIndices: (number | null)[][] = Array.from({ length: h }, () => Array(w).fill(null));
    const emptyQuantizedData: PixelData[][] = Array.from({ length: h }, () => Array(w).fill(null));

    if (validPixels.length === 0) {
      return { palette: [], pixelIndices: emptyIndices, quantizedData: emptyQuantizedData };
    }

    let centroids: RGBColor[] = [];
    const step = Math.floor(validPixels.length / k);
    for (let i = 0; i < k; i++) {
      centroids.push({ ...validPixels[Math.min(i * step, validPixels.length - 1)] });
    }

    for (let iter = 0; iter < 8; iter++) {
      const clusters: RGBColor[][] = Array.from({ length: k }, () => []);
      for (const p of validPixels) {
        let minDist = Infinity;
        let bestIdx = 0;
        centroids.forEach((c, idx) => {
          const dist = (p.r - c.r) ** 2 + (p.g - c.g) ** 2 + (p.b - c.b) ** 2;
          if (dist < minDist) {
            minDist = dist;
            bestIdx = idx;
          }
        });
        clusters[bestIdx].push(p);
      }

      centroids = clusters.map((group, idx) => {
        if (group.length === 0) return centroids[idx];
        const sum = group.reduce((acc, curr) => ({ r: acc.r + curr.r, g: acc.g + curr.g, b: acc.b + curr.b }), { r: 0, g: 0, b: 0 });
        return {
          r: Math.round(sum.r / group.length),
          g: Math.round(sum.g / group.length),
          b: Math.round(sum.b / group.length),
        };
      });
    }

    const pixelIndicesResult: (number | null)[][] = Array.from({ length: h }, () => Array(w).fill(null));
    const quantizedData: PixelData[][] = Array.from({ length: h }, () => Array(w).fill(null));

    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const p = rawPixels[y][x];
        if (p) {
          let minDist = Infinity;
          let bestIdx = 0;
          centroids.forEach((c, idx) => {
            const dist = (p.r - c.r) ** 2 + (p.g - c.g) ** 2 + (p.b - c.b) ** 2;
            if (dist < minDist) {
              minDist = dist;
              bestIdx = idx;
            }
          });
          pixelIndicesResult[y][x] = bestIdx;
          quantizedData[y][x] = centroids[bestIdx];
        }
      }
    }

    return { palette: centroids, pixelIndices: pixelIndicesResult, quantizedData };
  };

  const generateZigByteArray = (
    w: number,
    h: number,
    palette: RGBColor[],
    pIndices: (number | null)[][]
  ): Uint8Array => {
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

  const updateRenderOutput = (pIndices: (number | null)[][], palette: RGBColor[]) => {
    const canvas = document.createElement('canvas');
    canvas.width = cropWidth;
    canvas.height = cropHeight;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const imageData = ctx.createImageData(cropWidth, cropHeight);
    const data = imageData.data;

    for (let y = 0; y < cropHeight; y++) {
      for (let x = 0; x < cropWidth; x++) {
        const idx = (y * cropWidth + x) * 4;
        const colorIdx = pIndices[y]?.[x];
        if (colorIdx !== undefined && colorIdx !== null && palette[colorIdx]) {
          const color = palette[colorIdx];
          data[idx] = color.r;
          data[idx + 1] = color.g;
          data[idx + 2] = color.b;
          data[idx + 3] = 255;
        } else {
          data[idx + 3] = 0;
        }
      }
    }
    ctx.putImageData(imageData, 0, 0);

    const croppedImg = new Image();
    croppedImg.onload = () => setCroppedImage(croppedImg);
    croppedImg.src = canvas.toDataURL('image/png');

    const bin = generateZigByteArray(cropWidth, cropHeight, palette, pIndices);
    setByteArray(bin);
  };

  // 解析并装载二进制文件 (.bin)
  const handleBinUpload = (file: File) => {
    const reader = new FileReader();
    reader.onload = (evt) => {
      const buffer = new Uint8Array(evt.target?.result as ArrayBuffer);
      if (buffer.length < 5) return;

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

      setCropWidth(w);
      setCropHeight(h);
      setPixelIndices(pIndices);
      setOriginalPalette(palette);
      setCurrentPalette(palette);
      setColorCount(palette.length || 4);

      // 生成像素预览图像
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      if (ctx) {
        const imgData = ctx.createImageData(w, h);
        for (let y = 0; y < h; y++) {
          for (let x = 0; x < w; x++) {
            const pixelIdx = (y * w + x) * 4;
            const colorIdx = pIndices[y][x];
            if (colorIdx !== null && palette[colorIdx]) {
              const c = palette[colorIdx];
              imgData.data[pixelIdx] = c.r;
              imgData.data[pixelIdx + 1] = c.g;
              imgData.data[pixelIdx + 2] = c.b;
              imgData.data[pixelIdx + 3] = 255;
            } else {
              imgData.data[pixelIdx + 3] = 0;
            }
          }
        }
        ctx.putImageData(imgData, 0, 0);

        const binImg = new Image();
        binImg.onload = () => {
          setOriginalImage(binImg);
          setCroppedImage(binImg);
          setIsCropping(false);
        };
        binImg.src = canvas.toDataURL('image/png');
      }

      setByteArray(buffer);
    };
    reader.readAsArrayBuffer(file);
  };

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (file.name.endsWith('.bin')) {
      handleBinUpload(file);
      return;
    }

    const reader = new FileReader();
    reader.onload = (evt) => {
      const img = new Image();
      img.onload = () => {
        setOriginalImage(img);
        setCroppedImage(null);
        setIsCropping(true);

        const fitScale = Math.min(cropWidth / img.naturalWidth, cropHeight / img.naturalHeight);
        setScale(fitScale);
        setMinScale(fitScale * 0.2);
        setMaxScale(fitScale * 10);
        setImgOffset({
          x: (cropWidth - img.naturalWidth * fitScale) / 2,
          y: (cropHeight - img.naturalHeight * fitScale) / 2,
        });
      };
      img.src = evt.target?.result as string;
    };
    reader.readAsDataURL(file);
  };

  const handleApplyCropAndGenerate = () => {
    if (!originalImage) return;
    setIsProcessing(true);

    setTimeout(() => {
      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d');
      if (!ctx) return;

      canvas.width = cropWidth;
      canvas.height = cropHeight;
      ctx.clearRect(0, 0, cropWidth, cropHeight);

      ctx.drawImage(
        originalImage,
        imgOffset.x,
        imgOffset.y,
        originalImage.naturalWidth * scale,
        originalImage.naturalHeight * scale
      );

      const imageData = ctx.getImageData(0, 0, cropWidth, cropHeight);
      const data = imageData.data;

      const rawPixels: PixelData[][] = [];
      for (let y = 0; y < cropHeight; y++) {
        const row: PixelData[] = [];
        for (let x = 0; x < cropWidth; x++) {
          const idx = (y * cropWidth + x) * 4;
          const a = data[idx + 3];
          row.push(a === 0 ? null : { r: data[idx], g: data[idx + 1], b: data[idx + 2] });
        }
        rawPixels.push(row);
      }

      const { palette, pixelIndices: pIndices } = quantizePixels(rawPixels, colorCount, cropWidth, cropHeight);

      setPixelIndices(pIndices);
      setOriginalPalette(palette);
      setCurrentPalette(palette);

      updateRenderOutput(pIndices, palette);

      setIsCropping(false);
      setIsProcessing(false);
    }, 50);
  };

  const handleColorChange = (index: number, newColor: RGBColor) => {
    const updatedPalette = [...currentPalette];
    updatedPalette[index] = newColor;
    setCurrentPalette(updatedPalette);
    updateRenderOutput(pixelIndices, updatedPalette);
  };

  const handleResetSingleColor = (index: number) => {
    handleColorChange(index, originalPalette[index]);
  };

  const handleResetAllColors = () => {
    setCurrentPalette([...originalPalette]);
    updateRenderOutput(pixelIndices, originalPalette);
  };

  const updateScaleWithCenter = (newScale: number) => {
    const clampedScale = Math.min(Math.max(minScale, newScale), maxScale);
    const ratio = clampedScale / scale;
    const centerX = cropWidth / 2;
    const centerY = cropHeight / 2;
    setScale(clampedScale);
    setImgOffset({
      x: centerX - (centerX - imgOffset.x) * ratio,
      y: centerY - (centerY - imgOffset.y) * ratio,
    });
  };

  const resetState = () => {
    setOriginalImage(null);
    setCroppedImage(null);
    setPixelIndices([]);
    setOriginalPalette([]);
    setCurrentPalette([]);
    setEditingIndex(null);
    setByteArray(null);
    setIsCropping(false);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const downloadScript = () => {
    const element = document.createElement('a');
    const file = new Blob([finalScript], { type: 'text/plain' });
    element.href = URL.createObjectURL(file);
    element.download = 'tomodachi_macro.txt';
    document.body.appendChild(element);
    element.click();
    element.remove();
  };

  const downloadBinary = () => {
    if (!byteArray) return;
    const element = document.createElement('a');
    const file = new Blob([byteArray.buffer as ArrayBuffer], { type: 'application/octet-stream' });
    element.href = URL.createObjectURL(file);
    element.download = 'tomodachi_image.bin';
    document.body.appendChild(element);
    element.click();
    element.remove();
  };

  const hexPreview = useMemo(() => {
    if (!byteArray) return '';
    const slice = byteArray.slice(0, 128);
    const hex = Array.from(slice).map((b) => b.toString(16).padStart(2, '0')).join(' ');
    return byteArray.length > 128 ? `${hex} ... (共 ${byteArray.length} 字节)` : hex;
  }, [byteArray]);

  const finalScript = useMemo(() => {
    return generateZigMacroScriptBySegment(cropWidth, cropHeight, currentPalette, pixelIndices, delayMs);
  }, [cropWidth, cropHeight, delayMs, currentPalette, pixelIndices]);

  const VIEWPORT_WIDTH = Math.max(360, cropWidth + 80);
  const VIEWPORT_HEIGHT = Math.max(360, cropHeight + 80);
  const PADDING_X = (VIEWPORT_WIDTH - cropWidth) / 2;
  const PADDING_Y = (VIEWPORT_HEIGHT - cropHeight) / 2;

  return (
    <div className="" onMouseUp={() => setIsDragging(false)}>
      <header className="m3-header">
        {!originalImage && (
          <input
            type="file"
            accept="image/*,.bin"
            onChange={handleFileUpload}
            ref={fileInputRef}
            className="m3-input"
          />
        )}
      </header>

      {originalImage && (
        <main>
          <div style={{ textAlign: 'center', marginBottom: '16px' }}>
            <button className="m3-btn m3-btn-outlined" onClick={resetState}>
              重新选择文件
            </button>
          </div>

          {isCropping ? (
            <div className="m3-card">
              <div className="m3-controls-bar">
                <label className="m3-input-field">
                  宽度:
                  <input
                    type="number"
                    min="16"
                    max="512"
                    value={cropWidth}
                    onChange={(e) => {
                      const newWidth = Math.max(16, parseInt(e.target.value) || 256);
                      setCropWidth(newWidth);
                      if (originalImage) {
                        const fitScale = Math.min(newWidth / originalImage.naturalWidth, cropHeight / originalImage.naturalHeight);
                        setScale(fitScale);
                        setMinScale(fitScale * 0.2);
                        setMaxScale(fitScale * 10);
                        setImgOffset({
                          x: (newWidth - originalImage.naturalWidth * fitScale) / 2,
                          y: (cropHeight - originalImage.naturalHeight * fitScale) / 2,
                        });
                      }
                    }}
                    className="m3-input"
                    style={{ width: '100px' }}
                  />
                </label>

                <label className="m3-input-field">
                  高度:
                  <input
                    type="number"
                    min="16"
                    max="512"
                    value={cropHeight}
                    onChange={(e) => {
                      const newHeight = Math.max(16, parseInt(e.target.value) || 256);
                      setCropHeight(newHeight);
                      if (originalImage) {
                        const fitScale = Math.min(cropWidth / originalImage.naturalWidth, newHeight / originalImage.naturalHeight);
                        setScale(fitScale);
                        setMinScale(fitScale * 0.2);
                        setMaxScale(fitScale * 10);
                        setImgOffset({
                          x: (cropWidth - originalImage.naturalWidth * fitScale) / 2,
                          y: (newHeight - originalImage.naturalHeight * fitScale) / 2,
                        });
                      }
                    }}
                    className="m3-input"
                    style={{ width: '100px' }}
                  />
                </label>

                <label className="m3-input-field">
                  色彩数:
                  <input
                    type="number"
                    min="2"
                    max="256"
                    value={colorCount}
                    onChange={(e) => setColorCount(Math.min(256, Math.max(2, parseInt(e.target.value) || 2)))}
                    className="m3-input"
                    style={{ width: '100px' }}
                  />
                </label>

                <label className="m3-input-field">
                  缩放:
                  <input
                    type="range"
                    min={minScale}
                    max={maxScale}
                    step={(maxScale - minScale) / 100}
                    value={scale}
                    onChange={(e) => updateScaleWithCenter(parseFloat(e.target.value))}
                  />
                </label>

                <button
                  className="m3-btn m3-btn-filled"
                  onClick={handleApplyCropAndGenerate}
                  disabled={isProcessing}
                >
                  {isProcessing ? '生成中...' : '确认裁剪并生成数据与脚本'}
                </button>
              </div>

              <div
                className="m3-viewport-container"
                style={{
                  width: `${VIEWPORT_WIDTH}px`,
                  height: `${VIEWPORT_HEIGHT}px`,
                  cursor: isDragging ? 'grabbing' : 'grab',
                }}
                onMouseDown={(e) => {
                  e.preventDefault();
                  setIsDragging(true);
                  setDragStart({ x: e.clientX - imgOffset.x, y: e.clientY - imgOffset.y });
                }}
                onMouseMove={(e) => {
                  if (isDragging) setImgOffset({ x: e.clientX - dragStart.x, y: e.clientY - dragStart.y });
                }}
                onWheel={(e) => {
                  e.preventDefault();
                  updateScaleWithCenter(scale * (e.deltaY < 0 ? 1.1 : 0.9));
                }}
              >
                <img
                  src={originalImage.src}
                  alt="原图"
                  draggable={false}
                  style={{
                    position: 'absolute',
                    left: `${PADDING_X + imgOffset.x}px`,
                    top: `${PADDING_Y + imgOffset.y}px`,
                    width: `${originalImage.naturalWidth * scale}px`,
                    height: `${originalImage.naturalHeight * scale}px`,
                    pointerEvents: 'none',
                  }}
                />

                <div
                  className="m3-crop-box"
                  style={{
                    left: `${PADDING_X}px`,
                    top: `${PADDING_Y}px`,
                    width: `${cropWidth}px`,
                    height: `${cropHeight}px`,
                    boxShadow: '0 0 0 9999px rgba(0, 0, 0, 0.65)',
                  }}
                />
              </div>
            </div>
          ) : (
            <div className="m3-result-grid">
              {/* 左侧预览与调色板区 */}
              <div className="m3-card">
                <h3 className="m3-card-title" style={{ textAlign: 'center' }}>
                  图像预览 ({cropWidth}x{cropHeight})
                </h3>

                <div style={{ textAlign: 'center' }}>
                  {croppedImage && (
                    <img
                      src={croppedImage.src}
                      alt="量化图"
                      className="m3-preview-img"
                      style={{ width: `${cropWidth}px`, height: `${cropHeight}px`, maxWidth: '100%', objectFit: 'contain' }}
                    />
                  )}
                </div>

                <div className="m3-palette-bar">
                  <span style={{ fontSize: '14px', fontWeight: 600 }}>调色板:</span>
                  <button className="m3-btn m3-btn-danger" style={{ padding: '4px 12px' }} onClick={handleResetAllColors}>
                    全部重置
                  </button>
                </div>

                <div className="m3-palette-grid">
                  {currentPalette.map((c, idx) => {
                    const orig = originalPalette[idx];
                    const isModified = orig && (orig.r !== c.r || orig.g !== c.g || orig.b !== c.b);
                    return (
                      <div
                        key={idx}
                        className="m3-palette-chip"
                        onClick={() => setEditingIndex(idx)}
                        title={`Color ${idx + 1}: RGB(${c.r},${c.g},${c.b})${isModified ? ' (已修改)' : ''}`}
                        style={{
                          backgroundColor: `rgb(${c.r},${c.g},${c.b})`,
                          border: isModified ? '2px solid #eab308' : '1px solid rgba(255,255,255,0.4)',
                          color: (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) > 180 ? '#000' : '#fff',
                        }}
                      >
                        {idx + 1}
                      </div>
                    );
                  })}
                </div>

                {/* 二进制导出 Card */}
                <div style={{ marginTop: '20px', paddingTop: '16px', borderTop: '1px solid var(--md-color-outline-variant)' }}>
                  <h4 style={{ margin: '0 0 8px 0', fontSize: '14px' }}>Zig 格式字节数组</h4>
                  <p style={{ fontSize: '11px', fontFamily: 'monospace', color: 'var(--md-color-on-surface-variant)', wordBreak: 'break-all', margin: '0 0 12px 0' }}>
                    {hexPreview}
                  </p>
                  <button className="m3-btn m3-btn-tonal" style={{ width: '100%' }} onClick={downloadBinary}>
                    下载二进制 (.bin)
                  </button>
                </div>
              </div>

              {/* 右侧脚本输出区 */}
              <div className="m3-card">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                  <h3 className="m3-card-title" style={{ margin: 0 }}>宏脚本</h3>
                  <div style={{ display: 'flex', gap: '8px' }}>

                    <label className="m3-input-field">
                      延迟:
                      <input
                        type="number"
                        min="10"
                        max="1000"
                        value={delayMs}
                        onChange={(e) => setDelayMs(parseInt(e.target.value) || 80)}
                        className="m3-input"
                        style={{ width: '100px' }}
                      />
                    </label>
                    <button className="m3-btn m3-btn-outlined" onClick={() => navigator.clipboard.writeText(finalScript)}>
                      复制
                    </button>
                    <button className="m3-btn m3-btn-outlined" onClick={downloadScript}>
                      下载
                    </button>
                    <button className="m3-btn m3-btn-filled" onClick={() => onChangeScript(finalScript)}>
                      准备运行
                    </button>
                  </div>
                </div>

                <textarea readOnly value={finalScript} className="m3-code-block" />
              </div>
            </div>
          )}
        </main>
      )}

      {/* 颜色修改 Modal 弹窗 */}
      {editingIndex !== null && (
        <div className="color-modal-overlay" onClick={() => setEditingIndex(null)}>
          <div className="color-modal-content" onClick={(e) => e.stopPropagation()}>
            <h3 style={{ margin: '0 0 16px 0', fontSize: '1.125rem' }}>修改颜色 #{editingIndex + 1}</h3>

            <div style={{ display: 'flex', justifyContent: 'center', gap: '24px', marginBottom: '20px' }}>
              <div style={{ textAlign: 'center' }}>
                <p style={{ fontSize: '12px', margin: '0 0 6px 0', color: 'var(--md-color-on-surface-variant)' }}>当前 / 新颜色</p>
                <div
                  className="m3-color-preview-box"
                  style={{ backgroundColor: `rgb(${currentPalette[editingIndex].r},${currentPalette[editingIndex].g},${currentPalette[editingIndex].b})` }}
                />
              </div>

              <div style={{ textAlign: 'center' }}>
                <p style={{ fontSize: '12px', margin: '0 0 6px 0', color: 'var(--md-color-on-surface-variant)' }}>原始色</p>
                <div
                  className="m3-color-preview-box"
                  style={{ backgroundColor: `rgb(${originalPalette[editingIndex].r},${originalPalette[editingIndex].g},${originalPalette[editingIndex].b})` }}
                />
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', alignItems: 'center' }}>
              <label className="m3-input-field">
                选择颜色:
                <input
                  type="color"
                  value={rgbToHex(currentPalette[editingIndex])}
                  onChange={(e) => handleColorChange(editingIndex, hexToRgb(e.target.value))}
                  style={{ width: '40px', height: '36px', cursor: 'pointer', border: 'none', background: 'none' }}
                />
              </label>

              <div style={{ display: 'flex', gap: '8px' }}>
                <label className="m3-input-field">
                  R:
                  <input
                    type="number"
                    min="0"
                    max="255"
                    value={currentPalette[editingIndex].r}
                    onChange={(e) =>
                      handleColorChange(editingIndex, {
                        ...currentPalette[editingIndex],
                        r: Math.min(255, Math.max(0, parseInt(e.target.value) || 0)),
                      })
                    }
                    className="m3-input"
                    style={{ width: '50px' }}
                  />
                </label>
                <label className="m3-input-field">
                  G:
                  <input
                    type="number"
                    min="0"
                    max="255"
                    value={currentPalette[editingIndex].g}
                    onChange={(e) =>
                      handleColorChange(editingIndex, {
                        ...currentPalette[editingIndex],
                        g: Math.min(255, Math.max(0, parseInt(e.target.value) || 0)),
                      })
                    }
                    className="m3-input"
                    style={{ width: '50px' }}
                  />
                </label>
                <label className="m3-input-field">
                  B:
                  <input
                    type="number"
                    min="0"
                    max="255"
                    value={currentPalette[editingIndex].b}
                    onChange={(e) =>
                      handleColorChange(editingIndex, {
                        ...currentPalette[editingIndex],
                        b: Math.min(255, Math.max(0, parseInt(e.target.value) || 0)),
                      })
                    }
                    className="m3-input"
                    style={{ width: '50px' }}
                  />
                </label>
              </div>
            </div>

            <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: '24px' }}>
              <button
                className="m3-btn m3-btn-outlined"
                onClick={() => handleResetSingleColor(editingIndex)}
              >
                还原原始值
              </button>
              <button
                className="m3-btn m3-btn-filled"
                onClick={() => setEditingIndex(null)}
              >
                确定
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default TomodachiLifeNormal;