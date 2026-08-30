import React, { useState, useEffect, useRef, useCallback } from 'react';
import { type RGBColor, rgbToHex, hexToRgb } from './color';
import { loadImageFromZigByteArray, generateZigByteArray, type Image as ImageStruct } from './image';

export interface ImageEditorModalProps {
  /** 输入的 Image 二进制流数组 */
  byteArray: Uint8Array;
  /** 点击确定后触发的回调，返回更新后的二进制流数组 */
  onConfirm: (updatedByteArray: Uint8Array) => void;
  /** 关闭弹窗 */
  onClose: () => void;
}

export const ImageEditorModal: React.FC<ImageEditorModalProps> = ({
  byteArray,
  onConfirm,
  onClose,
}) => {
  const [imageStruct, setImageStruct] = useState<ImageStruct | null>(null);
  const [palette, setPalette] = useState<RGBColor[]>([]);
  const [pIndices, setPIndices] = useState<(number | null)[][]>([]);

  // 当前选中的色槽索引，null 表示“橡皮擦/删除单元格颜色”
  const [selectedColorIdx, setSelectedColorIdx] = useState<number | null>(0);
  
  // 单元格像素缩放大小 (像素)
  const [cellSize, setCellSize] = useState<number>(24);
  
  // 鼠标拖拽绘制状态
  const [isMouseDown, setIsMouseDown] = useState<boolean>(false);
  
  // 预览弹窗控制
  const [showPreviewModal, setShowPreviewModal] = useState<boolean>(false);

  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const previewCanvasRef = useRef<HTMLCanvasElement | null>(null);

  // 1. 初始化：解析二进制数组
  useEffect(() => {
    if (!byteArray || byteArray.length === 0) return;
    const img = loadImageFromZigByteArray(byteArray);
    if (!img) return;

    setImageStruct(img);
    setPalette([...img.palette]);

    const w = img.width;
    const h = img.height;

    const normalizedIndices: (number | null)[][] = Array.from({ length: h }, (_, y) => {
      const row = img.pIndices[y] || [];
      const fullRow: (number | null)[] = new Array(w).fill(null);
      for (let x = 0; x < w; x++) {
        fullRow[x] = row[x] !== undefined ? row[x] : null;
      }
      return fullRow;
    });

    setPIndices(normalizedIndices);
    setSelectedColorIdx(img.palette.length > 0 ? 0 : null);
  }, [byteArray]);

  // 计算文本颜色对比度 (黑/白)
  const getContrastTextColor = (color: RGBColor) => {
    const yiq = (color.r * 299 + color.g * 587 + color.b * 114) / 1000;
    return yiq >= 128 ? '#000000' : '#ffffff';
  };

  // 2. 渲染二维单元格网格
  const renderGrid = useCallback(() => {
    if (!imageStruct || !canvasRef.current || pIndices.length === 0) return;
    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const { width, height } = imageStruct;
    const totalWidth = width * cellSize;
    const totalHeight = height * cellSize;

    // 显式设置 Canvas 物理像素缓冲区大小
    canvas.width = totalWidth;
    canvas.height = totalHeight;

    // 【关键修复】：显式强制 CSS 宽高，防止被全局 CSS (如 max-width: 100%) 强行拉伸/压扁
    canvas.style.width = `${totalWidth}px`;
    canvas.style.height = `${totalHeight}px`;
    canvas.style.maxWidth = 'none';

    ctx.clearRect(0, 0, totalWidth, totalHeight);

    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const px = x * cellSize;
        const py = y * cellSize;
        const colorIdx = pIndices[y]?.[x];

        // 绘制单元格背景色
        if (colorIdx !== null && colorIdx !== undefined && palette[colorIdx]) {
          const c = palette[colorIdx];
          ctx.fillStyle = `rgb(${c.r}, ${c.g}, ${c.b})`;
          ctx.fillRect(px, py, cellSize, cellSize);
        } else {
          // 无颜色时填充棋盘格图案
          ctx.fillStyle = (x + y) % 2 === 0 ? '#ffffff' : '#e0e0e0';
          ctx.fillRect(px, py, cellSize, cellSize);
        }

        // 绘制边框
        ctx.strokeStyle = 'rgba(0, 0, 0, 0.15)';
        ctx.lineWidth = 1;
        ctx.strokeRect(px, py, cellSize, cellSize);

        // 绘制颜色编号 (单元格尺寸 ≥ 16px 时显示)
        if (cellSize >= 16) {
          ctx.font = `${Math.max(10, Math.floor(cellSize * 0.4))}px sans-serif`;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';

          if (colorIdx !== null && colorIdx !== undefined && palette[colorIdx]) {
            ctx.fillStyle = getContrastTextColor(palette[colorIdx]);
            ctx.fillText(`${colorIdx + 1}`, px + cellSize / 2, py + cellSize / 2);
          } else {
            ctx.fillStyle = '#999999';
            ctx.fillText('-', px + cellSize / 2, py + cellSize / 2);
          }
        }
      }
    }
  }, [imageStruct, palette, pIndices, cellSize]);

  useEffect(() => {
    renderGrid();
  }, [renderGrid]);

  // 3. 处理单元格交互（带有 DOM 坐标缩放映射）
  const handleCellInteract = (e: React.MouseEvent<HTMLCanvasElement>) => {
    if (!imageStruct || !canvasRef.current) return;
    const canvas = canvasRef.current;
    const rect = canvas.getBoundingClientRect();

    // 【关键修复】：根据 Canvas 真实像素与 DOM 显式尺寸进行比例换算，防止坐标错位
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;

    const clickX = (e.clientX - rect.left) * scaleX;
    const clickY = (e.clientY - rect.top) * scaleY;

    const x = Math.floor(clickX / cellSize);
    const y = Math.floor(clickY / cellSize);

    if (x >= 0 && x < imageStruct.width && y >= 0 && y < imageStruct.height) {
      setPIndices((prev) => {
        if (prev[y]?.[x] === selectedColorIdx) return prev;
        const next = prev.map((row) => [...row]);
        next[y][x] = selectedColorIdx;
        return next;
      });
    }
  };

  const handleMouseDown = (e: React.MouseEvent<HTMLCanvasElement>) => {
    setIsMouseDown(true);
    handleCellInteract(e);
  };

  const handleMouseMove = (e: React.MouseEvent<HTMLCanvasElement>) => {
    if (isMouseDown) {
      handleCellInteract(e);
    }
  };

  const handleMouseUp = () => {
    setIsMouseDown(false);
  };

  // 4. 调色板编辑操作
  const handleAddColor = () => {
    const newColor: RGBColor = { r: 255, g: 0, b: 0 };
    setPalette((prev) => [...prev, newColor]);
    setSelectedColorIdx(palette.length);
  };

  const handleUpdateColor = (index: number, hex: string) => {
    const newColor = hexToRgb(hex);
    setPalette((prev) => {
      const next = [...prev];
      next[index] = newColor;
      return next;
    });
  };

  const handleDeleteColor = (index: number) => {
    setPalette((prev) => prev.filter((_, i) => i !== index));

    setPIndices((prevIndices) =>
      prevIndices.map((row) =>
        row.map((colorIdx) => {
          if (colorIdx === index) return null;
          if (colorIdx !== null && colorIdx > index) return colorIdx - 1;
          return colorIdx;
        })
      )
    );

    if (selectedColorIdx === index) {
      setSelectedColorIdx(null);
    } else if (selectedColorIdx !== null && selectedColorIdx > index) {
      setSelectedColorIdx(selectedColorIdx - 1);
    }
  };

  // 5. 渲染 1:1 实际原图预览
  const renderActualPreview = useCallback(() => {
    if (!imageStruct || !previewCanvasRef.current) return;
    const canvas = previewCanvasRef.current;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const { width, height } = imageStruct;
    canvas.width = width;
    canvas.height = height;

    const imgData = ctx.createImageData(width, height);
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const pixelIdx = (y * width + x) * 4;
        const colorIdx = pIndices[y]?.[x];
        if (colorIdx !== null && colorIdx !== undefined && palette[colorIdx]) {
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
  }, [imageStruct, palette, pIndices]);

  useEffect(() => {
    if (showPreviewModal) {
      renderActualPreview();
    }
  }, [showPreviewModal, renderActualPreview]);

  // 6. 点击确定：重新编码并关闭
  const handleConfirm = () => {
    if (!imageStruct) return;
    const newBinary = generateZigByteArray({
      width: imageStruct.width,
      height: imageStruct.height,
      palette,
      pIndices,
    });
    onConfirm(newBinary);
    onClose();
  };

  if (!imageStruct) return null;

  return (
    <div className="color-modal-overlay" onClick={onClose}>
      <div
        className="m3-editor-modal-container"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="m3-editor-header">
          <h3>
            图像二维网格编辑器 ({imageStruct.width} × {imageStruct.height})
          </h3>
          <button className="m3-btn-icon" onClick={onClose}>✕</button>
        </div>

        <div className="m3-editor-toolbar">
          <div className="m3-input-field">
            <label>单元格大小 ({cellSize}px):</label>
            <input
              type="range"
              min="1"
              max="100"
              value={cellSize}
              onChange={(e) => setCellSize(Number(e.target.value))}
            />
          </div>

          <div>
            <button
              className="m3-btn m3-btn-outlined"
              onClick={() => setShowPreviewModal(true)}
            >
              预览
            </button>
          </div>
        </div>

        {/* 调色板选色 */}
        <div className="m3-editor-palette-bar">
          <span style={{ fontSize: '0.875rem', fontWeight: 600 }}>调色板:</span>

          <div
            className={`m3-palette-chip-editor ${selectedColorIdx === null ? 'selected' : ''}`}
            onClick={() => setSelectedColorIdx(null)}
            title="橡皮擦"
            style={{ background: '#eee', color: '#333' }}
          >
            清除
          </div>

          {palette.map((color, idx) => (
            <div
              key={idx}
              className={`m3-palette-chip-editor ${selectedColorIdx === idx ? 'selected' : ''}`}
              onClick={() => setSelectedColorIdx(idx)}
              style={{ backgroundColor: `rgb(${color.r},${color.g},${color.b})` }}
            >
              <span
                className="m3-chip-number"
                style={{ color: getContrastTextColor(color) }}
              >
                #{idx + 1}
              </span>

              <input
                type="color"
                value={rgbToHex(color)}
                onClick={(e) => e.stopPropagation()}
                onChange={(e) => handleUpdateColor(idx, e.target.value)}
              />

              <button
                className="m3-chip-delete-btn m3-chip-pick-btn"
                title='选择'
                onClick={(e) => {
                  e.stopPropagation();
                  setSelectedColorIdx(idx);
                }}
              >
                ◎
              </button>
              <button
                className="m3-chip-delete-btn"
                title='删除'
                onClick={(e) => {
                  e.stopPropagation();
                  handleDeleteColor(idx);
                }}
              >
                ×
              </button>
            </div>
          ))}

          <button
            className="m3-btn m3-btn-outlined"
            style={{ padding: '4px 12px', fontSize: '0.75rem' }}
            onClick={handleAddColor}
          >
            + 添加颜色
          </button>
        </div>

        {/* 滚动面板 */}
        <div className="m3-editor-grid-scroll-panel">
          <canvas
            ref={canvasRef}
            onMouseDown={handleMouseDown}
            onMouseMove={handleMouseMove}
            onMouseUp={handleMouseUp}
            onMouseLeave={handleMouseUp}
            style={{ cursor: selectedColorIdx === null ? 'cell' : 'crosshair' }}
          />
        </div>

        <div className="m3-editor-footer">
          <button className="m3-btn m3-btn-outlined" onClick={onClose}>
            取消
          </button>
          <button className="m3-btn m3-btn-filled" onClick={handleConfirm}>
            完成
          </button>
        </div>
      </div>

      {/* 预览弹窗 */}
      {showPreviewModal && (
        <div className="color-modal-overlay" onClick={() => setShowPreviewModal(false)}>
          <div
            className="m3-preview-modal-content"
            onClick={(e) => e.stopPropagation()}
          >
            <h4>实际大小原图预览 (1:1)</h4>
            <div className="m3-preview-canvas-box">
              <canvas ref={previewCanvasRef} />
            </div>
            <p style={{ fontSize: '0.75rem', color: 'var(--md-color-on-surface-variant)', marginTop: '8px' }}>
              尺寸: {imageStruct.width} × {imageStruct.height} px
            </p>
            <div style={{ textAlign: 'right', marginTop: '16px' }}>
              <button className="m3-btn m3-btn-filled" onClick={() => setShowPreviewModal(false)}>
                关闭
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ImageEditorModal;