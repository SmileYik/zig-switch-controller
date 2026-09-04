import type { PixelData, RGBColor } from "./color";

export interface QuantizedPixels {
  palette: RGBColor[];
  pixelIndices: (number | null)[][];
  quantizedData: PixelData[][];
};

export type QuantizeFunction = (rawPixels: PixelData[][], k: number, width: number, height: number) => QuantizedPixels;

const quantizePixelsNormal = (rawPixels: PixelData[][], k: number, w: number, h: number): QuantizedPixels => {
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

export type QuantizeType = "normal";
export interface QuantizeAlgorithm {
  type: QuantizeType,
  quantize: QuantizeFunction,
};
export const QuantizeAlgorithmMap: Record<QuantizeType, QuantizeAlgorithm> = {
  "normal": { type: "normal", quantize: quantizePixelsNormal }
};