import type { PixelData, RGBColor } from "./color";

export interface QuantizedPixels {
  palette: RGBColor[];
  pixelIndices: (number | null)[][];
  quantizedData: PixelData[][];
}

export type QuantizeFunction = (
  rawPixels: PixelData[][],
  k: number,
  width: number,
  height: number,
) => QuantizedPixels;

type WeightedPixel = {
  color: RGBColor;
  weight: number;
};

const rgbDistSq = (a: RGBColor, b: RGBColor): number =>
  (a.r - b.r) ** 2 + (a.g - b.g) ** 2 + (a.b - b.b) ** 2;

const clampInt = (value: number, min: number, max: number): number =>
  Math.min(max, Math.max(min, Math.round(value)));

const createEmptyResult = (w: number, h: number): QuantizedPixels => ({
  palette: [],
  pixelIndices: Array.from({ length: h }, () => Array(w).fill(null)),
  quantizedData: Array.from({ length: h }, () => Array(w).fill(null)),
});

/**
 * 计算每个不透明像素距离透明区域的 4-neighbor 曼哈顿距离。
 * null 被视为透明区，距离为 0。
 */
const buildDistanceToTransparent = (
  rawPixels: PixelData[][],
  w: number,
  h: number,
): number[][] => {
  const INF = Number.MAX_SAFE_INTEGER;
  const dist = Array.from({ length: h }, () => Array(w).fill(INF));
  const queueX = new Int32Array(w * h);
  const queueY = new Int32Array(w * h);
  let head = 0;
  let tail = 0;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!rawPixels[y][x]) {
        dist[y][x] = 0;
        queueX[tail] = x;
        queueY[tail] = y;
        tail++;
      }
    }
  }

  const dx = [1, -1, 0, 0];
  const dy = [0, 0, 1, -1];

  while (head < tail) {
    const x = queueX[head];
    const y = queueY[head];
    head++;

    const nextDistance = dist[y][x] + 1;
    for (let i = 0; i < 4; i++) {
      const nx = x + dx[i];
      const ny = y + dy[i];
      if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
      if (nextDistance < dist[ny][nx]) {
        dist[ny][nx] = nextDistance;
        queueX[tail] = nx;
        queueY[tail] = ny;
        tail++;
      }
    }
  }

  return dist;
};

const getLocalInteriorColor = (
  rawPixels: PixelData[][],
  edgeDistance: number[][],
  x: number,
  y: number,
  radius: number,
): { color: RGBColor; count: number } | null => {
  const w = rawPixels[0]?.length ?? 0;
  const h = rawPixels.length;
  let sumR = 0;
  let sumG = 0;
  let sumB = 0;
  let totalWeight = 0;
  let count = 0;

  // 只用离透明区足够远的像素估计“真正的内部颜色”。
  const minCoreDistance = Math.max(2, radius);

  for (let oy = -radius; oy <= radius; oy++) {
    for (let ox = -radius; ox <= radius; ox++) {
      if (ox === 0 && oy === 0) continue;

      const nx = x + ox;
      const ny = y + oy;
      if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;

      const p = rawPixels[ny][nx];
      if (!p || edgeDistance[ny][nx] < minCoreDistance) continue;

      const d2 = ox * ox + oy * oy;
      if (d2 > radius * radius) continue;

      const weight = 1 / Math.max(1, d2);
      sumR += p.r * weight;
      sumG += p.g * weight;
      sumB += p.b * weight;
      totalWeight += weight;
      count++;
    }
  }

  if (count === 0 || totalWeight === 0) return null;

  return {
    color: {
      r: sumR / totalWeight,
      g: sumG / totalWeight,
      b: sumB / totalWeight,
    },
    count,
  };
};

/**
 * 判断边缘像素是否很像“抠图残色”：
 * 1. 离透明区很近；
 * 2. 和内部主色明显不同；
 * 3. 自己的颜色在附近缺乏足够连续支持。
 *
 * 这比简单的“边缘像素全部当噪声”安全，因为真实的黑色描边通常会形成
 * 连续的同色带，因此不会轻易被判为污染。
 */
const buildEdgeContaminationMask = (
  rawPixels: PixelData[][],
  edgeDistance: number[][],
  w: number,
  h: number,
): boolean[][] => {
  const mask = Array.from({ length: h }, () => Array(w).fill(false));

  const neighborhoodRadius = 2;
  const sameColorThresholdSq = 28 ** 2;
  const interiorDifferenceThresholdSq = 68 ** 2;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const p = rawPixels[y][x];
      if (!p) continue;

      // distance=1 表示它直接贴着透明区，是最值得怀疑的区域。
      // distance=2 也纳入，但判定会更严格。
      if (edgeDistance[y][x] > 2) continue;

      const interior = getLocalInteriorColor(rawPixels, edgeDistance, x, y, 3);
      if (!interior || interior.count < 2) continue;

      const interiorDiff = rgbDistSq(p, interior.color);

      let validNeighborCount = 0;
      let sameColorNeighborCount = 0;

      for (let oy = -neighborhoodRadius; oy <= neighborhoodRadius; oy++) {
        for (let ox = -neighborhoodRadius; ox <= neighborhoodRadius; ox++) {
          if (ox === 0 && oy === 0) continue;

          const nx = x + ox;
          const ny = y + oy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;

          const np = rawPixels[ny][nx];
          if (!np) continue;

          validNeighborCount++;
          if (rgbDistSq(p, np) <= sameColorThresholdSq) {
            sameColorNeighborCount++;
          }
        }
      }

      const sameSupportRatio = validNeighborCount === 0
        ? 0
        : sameColorNeighborCount / validNeighborCount;

      // distance=1 时允许更积极地剔除；distance=2 只剔除非常孤立的异常色。
      const isolatedEnough =
        sameColorNeighborCount <= (edgeDistance[y][x] === 1 ? 3 : 1) ||
        sameSupportRatio < 0.18;

      if (interiorDiff >= interiorDifferenceThresholdSq && isolatedEnough) {
        mask[y][x] = true;
      }
    }
  }

  return mask;
};

const computePixelWeight = (
  edgeDistance: number,
  contaminated: boolean,
): number => {
  if (contaminated) return 0.03;

  // 让透明边缘的抗锯齿/背景残色极难成为调色板中心，
  // 但仍保留少量权重，以免真实描边颜色被完全忽略。
  if (edgeDistance <= 0) return 0.03;
  if (edgeDistance === 1) return 0.16;
  if (edgeDistance === 2) return 0.55;
  return 1;
};

const initializeCentroids = (
  samples: WeightedPixel[],
  k: number,
): RGBColor[] => {
  if (samples.length === 0 || k <= 0) return [];

  const actualK = Math.min(k, samples.length);
  const centroids: RGBColor[] = [];

  // 第一颗选择权重最高的像素，优先从内部颜色开始。
  let firstIndex = 0;
  for (let i = 1; i < samples.length; i++) {
    if (samples[i].weight > samples[firstIndex].weight) {
      firstIndex = i;
    }
  }
  centroids.push({ ...samples[firstIndex].color });

  while (centroids.length < actualK) {
    let bestIndex = 0;
    let bestScore = -Infinity;

    for (let i = 0; i < samples.length; i++) {
      let nearestDist = Infinity;
      for (const centroid of centroids) {
        nearestDist = Math.min(nearestDist, rgbDistSq(samples[i].color, centroid));
      }

      // 权重越高、离已有中心越远，越值得作为新的 palette 起点。
      const score = nearestDist * samples[i].weight;
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    centroids.push({ ...samples[bestIndex].color });
  }

  return centroids;
};

const weightedKMeans = (
  samples: WeightedPixel[],
  k: number,
  iterations = 10,
): RGBColor[] => {
  const centroids = initializeCentroids(samples, k);
  if (centroids.length === 0) return [];

  for (let iter = 0; iter < iterations; iter++) {
    const sumR = new Array(centroids.length).fill(0);
    const sumG = new Array(centroids.length).fill(0);
    const sumB = new Array(centroids.length).fill(0);
    const sumWeight = new Array(centroids.length).fill(0);

    for (const sample of samples) {
      let bestIndex = 0;
      let minDist = Infinity;

      for (let i = 0; i < centroids.length; i++) {
        const dist = rgbDistSq(sample.color, centroids[i]);
        if (dist < minDist) {
          minDist = dist;
          bestIndex = i;
        }
      }

      const w = sample.weight;
      sumR[bestIndex] += sample.color.r * w;
      sumG[bestIndex] += sample.color.g * w;
      sumB[bestIndex] += sample.color.b * w;
      sumWeight[bestIndex] += w;
    }

    for (let i = 0; i < centroids.length; i++) {
      if (sumWeight[i] <= 0) continue;

      centroids[i] = {
        r: clampInt(sumR[i] / sumWeight[i], 0, 255),
        g: clampInt(sumG[i] / sumWeight[i], 0, 255),
        b: clampInt(sumB[i] / sumWeight[i], 0, 255),
      };
    }
  }

  return centroids;
};

const nearestPaletteIndex = (
  pixel: RGBColor,
  palette: RGBColor[],
): number => {
  let bestIndex = 0;
  let minDist = Infinity;

  for (let i = 0; i < palette.length; i++) {
    const dist = rgbDistSq(pixel, palette[i]);
    if (dist < minDist) {
      minDist = dist;
      bestIndex = i;
    }
  }

  return bestIndex;
};

/**
 * 对疑似边缘毛刺执行“向内部吸附”：
 * 只在 edgeContaminationMask=true 的情况下修改标签，避免误伤真实描边。
 */
const repairContaminatedEdgeLabels = (
  rawPixels: PixelData[][],
  edgeDistance: number[][],
  contaminationMask: boolean[][],
  pixelIndices: (number | null)[][],
  w: number,
  h: number,
): void => {
  const radius = 2;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!contaminationMask[y][x]) continue;
      if (!rawPixels[y][x]) continue;

      const scoreByLabel = new Map<number, number>();

      for (let oy = -radius; oy <= radius; oy++) {
        for (let ox = -radius; ox <= radius; ox++) {
          if (ox === 0 && oy === 0) continue;

          const nx = x + ox;
          const ny = y + oy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;

          const neighbor = rawPixels[ny][nx];
          const label = pixelIndices[ny][nx];
          if (!neighbor || label === null) continue;

          // 尽量只向内部颜色吸附，不从另一个边缘毛刺复制颜色。
          if (edgeDistance[ny][nx] < 2) continue;

          const d2 = ox * ox + oy * oy;
          const weight = 1 / Math.max(1, d2);
          scoreByLabel.set(label, (scoreByLabel.get(label) ?? 0) + weight);
        }
      }

      if (scoreByLabel.size === 0) continue;

      let bestLabel = pixelIndices[y][x];
      let bestScore = -Infinity;
      for (const [label, score] of scoreByLabel) {
        if (score > bestScore) {
          bestScore = score;
          bestLabel = label;
        }
      }

      if (bestLabel !== null) {
        pixelIndices[y][x] = bestLabel;
      }
    }
  }
};

/**
 * 对 quantized label 做一次非常保守的“孤立点去毛刺”。
 * 仅处理透明边缘附近，而且要求候选标签拥有明显邻域优势。
 */
const smoothBoundarySpecks = (
  rawPixels: PixelData[][],
  edgeDistance: number[][],
  pixelIndices: (number | null)[][],
  w: number,
  h: number,
): void => {
  const original = pixelIndices.map((row) => [...row]);
  const radius = 1;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!rawPixels[y][x] || edgeDistance[y][x] > 2) continue;

      const currentLabel = original[y][x];
      if (currentLabel === null) continue;

      const counts = new Map<number, number>();
      let sameCount = 0;

      for (let oy = -radius; oy <= radius; oy++) {
        for (let ox = -radius; ox <= radius; ox++) {
          if (ox === 0 && oy === 0) continue;

          const nx = x + ox;
          const ny = y + oy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;

          const label = original[ny][nx];
          if (label === null) continue;

          counts.set(label, (counts.get(label) ?? 0) + 1);
          if (label === currentLabel) sameCount++;
        }
      }

      if (sameCount >= 2) continue;

      let bestLabel = currentLabel;
      let bestCount = sameCount;
      for (const [label, count] of counts) {
        if (label !== currentLabel && count > bestCount) {
          bestLabel = label;
          bestCount = count;
        }
      }

      // 至少需要 4 个邻居明确支持另一个颜色，避免吃掉正常 1px 描边。
      if (bestLabel !== currentLabel && bestCount >= 4) {
        pixelIndices[y][x] = bestLabel;
      }
    }
  }
};

/**
 * 新的“Q版 / 线稿友好”像素量化：
 * - 调色板学习时降低透明边缘像素权重；
 * - 对疑似抠图残色做局部内部颜色吸附；
 * - 最后只对边缘孤立点做极保守的去毛刺。
 *
 * 输出依然是纯 palette 色，不做 dithering，因此非常适合 Android/emoji 风格的扁平色块。
 */
export const quantizePixelsSmooth = (
  rawPixels: PixelData[][],
  k: number,
  w: number,
  h: number,
): QuantizedPixels => {
  const empty = createEmptyResult(w, h);

  if (k <= 0 || w <= 0 || h <= 0) return empty;

  const distanceToTransparent = buildDistanceToTransparent(rawPixels, w, h);
  const contaminationMask = buildEdgeContaminationMask(
    rawPixels,
    distanceToTransparent,
    w,
    h,
  );

  const samples: WeightedPixel[] = [];
  let validPixelCount = 0;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const p = rawPixels[y][x];
      if (!p) continue;

      validPixelCount++;
      samples.push({
        color: p,
        weight: computePixelWeight(
          distanceToTransparent[y][x],
          contaminationMask[y][x],
        ),
      });
    }
  }

  if (validPixelCount === 0) return empty;

  const palette = weightedKMeans(samples, Math.min(k, validPixelCount), 10);
  if (palette.length === 0) return empty;

  const pixelIndices: (number | null)[][] = Array.from(
    { length: h },
    () => Array(w).fill(null),
  );
  const quantizedData: PixelData[][] = Array.from(
    { length: h },
    () => Array(w).fill(null),
  );

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const p = rawPixels[y][x];
      if (!p) continue;

      const label = nearestPaletteIndex(p, palette);
      pixelIndices[y][x] = label;
      quantizedData[y][x] = palette[label];
    }
  }

  repairContaminatedEdgeLabels(
    rawPixels,
    distanceToTransparent,
    contaminationMask,
    pixelIndices,
    w,
    h,
  );

  smoothBoundarySpecks(
    rawPixels,
    distanceToTransparent,
    pixelIndices,
    w,
    h,
  );

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const label = pixelIndices[y][x];
      quantizedData[y][x] = label === null ? null : palette[label];
    }
  }

  return {
    palette,
    pixelIndices,
    quantizedData,
  };
};

// 保留原有普通量化函数，方便 A/B 测试。
const quantizePixelsNormal = (
  rawPixels: PixelData[][],
  k: number,
  w: number,
  h: number,
): QuantizedPixels => {
  const empty = createEmptyResult(w, h);
  const validPixels: RGBColor[] = [];

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const p = rawPixels[y][x];
      if (p) validPixels.push(p);
    }
  }

  if (validPixels.length === 0 || k <= 0) return empty;

  let centroids = initializeCentroids(
    validPixels.map((color) => ({ color, weight: 1 })),
    Math.min(k, validPixels.length),
  );

  for (let iter = 0; iter < 8; iter++) {
    const sumR = new Array(centroids.length).fill(0);
    const sumG = new Array(centroids.length).fill(0);
    const sumB = new Array(centroids.length).fill(0);
    const count = new Array(centroids.length).fill(0);

    for (const p of validPixels) {
      const idx = nearestPaletteIndex(p, centroids);
      sumR[idx] += p.r;
      sumG[idx] += p.g;
      sumB[idx] += p.b;
      count[idx]++;
    }

    for (let i = 0; i < centroids.length; i++) {
      if (count[i] === 0) continue;
      centroids[i] = {
        r: clampInt(sumR[i] / count[i], 0, 255),
        g: clampInt(sumG[i] / count[i], 0, 255),
        b: clampInt(sumB[i] / count[i], 0, 255),
      };
    }
  }

  const pixelIndices = Array.from(
    { length: h },
    () => Array(w).fill(null),
  );
  const quantizedData: PixelData[][] = Array.from(
    { length: h },
    () => Array(w).fill(null),
  );

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const p = rawPixels[y][x];
      if (!p) continue;
      const idx = nearestPaletteIndex(p, centroids);
      pixelIndices[y][x] = idx;
      quantizedData[y][x] = centroids[idx];
    }
  }

  return {
    palette: centroids,
    pixelIndices,
    quantizedData,
  };
};

export type QuantizeType = "normal" | "smooth";

export interface QuantizeAlgorithm {
  type: QuantizeType;
  quantize: QuantizeFunction;
}

export const QuantizeAlgorithmMap: Record<QuantizeType, QuantizeAlgorithm> = {
  normal: { type: "normal", quantize: quantizePixelsNormal },
  smooth: { type: "smooth", quantize: quantizePixelsSmooth },
};
