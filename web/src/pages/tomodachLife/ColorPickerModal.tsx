import { hexToRgb, rgbToHex, type RGBColor } from "./color";

export interface ColorPickerModalProps {
  editingIndex: number,
  originalPalette: RGBColor[],
  currentPalette: RGBColor[],
  onColorChange: (colors: RGBColor[]) => void;
  onClose: () => void;
};

const ColorPickerModal = (
  {
    editingIndex,
    originalPalette,
    currentPalette,
    onColorChange,
    onClose,
  }: ColorPickerModalProps
) => {
  const handleColorChange = (idx: number, color: RGBColor) => {
    const updatedPalette = [...currentPalette];
    updatedPalette[idx] = color;
    onColorChange(updatedPalette);
  }

  return (
    <div className="color-modal-overlay" onClick={onClose}>
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
            onClick={() => {handleColorChange(editingIndex, originalPalette[editingIndex]); onClose();}}
          >
            还原原始值
          </button>
          <button
            className="m3-btn m3-btn-filled"
            onClick={onClose}
          >
            确定
          </button>
        </div>
      </div>
    </div>
  )
}

export default ColorPickerModal;