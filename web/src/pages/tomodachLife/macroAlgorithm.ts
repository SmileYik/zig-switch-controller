import { rgbToTomodachiHSV, type RGBColor } from "./color";

export type MacroGenerator = (
  w: number,
  h: number,
  palette: RGBColor[],
  pIndices: (number | null)[][],
  delay: number
) => string;

type Point = {
  x: number;
  y: number;
};

export interface ZigMacroScriptContext {
  readonly w: number;
  readonly h: number;
  readonly palette: RGBColor[];
  readonly pIndices: (number | null)[][];
  readonly delay: number;

  readonly lines: string[];

  curX: number;
  curY: number;
  curColorPanelIdx: number;

  tap(button: string, space?: number): void;
  tapMultiple(button: string, count: number): void;
  wait(ms: number): void;
  down(button: string): void;
  up(button: string): void;

  initColorPanel(): void;
  chooseColorPanel(idx: number): void;
  resetHSVColorPanel(): void;
  chooseHSVColor(slotIdx: number, colorIdx: number): void;

  moveTo(targetX: number, targetY: number): void;
  getId(x: number, y: number): number;
  manhattanDistance(a: Point, b: Point): number;
  directionFromTo(from: Point, to: Point): string;
}

const createZigMacroScriptContext = (
  w: number,
  h: number,
  palette: RGBColor[],
  pIndices: (number | null)[][],
  delay: number
): ZigMacroScriptContext => {
  const context: ZigMacroScriptContext = {
    w,
    h,
    palette,
    pIndices,
    delay,
    lines: [],
    curX: 0,
    curY: 0,
    curColorPanelIdx: 0,

    tap: (button, space = 0) => context.lines.push(`${' '.repeat(space)}TAP ${delay}ms ${delay}ms ${button}`),

    tapMultiple: (button, count) => {
      if (count <= 0) return;
      if (count === 1) {
        context.tap(button);
        return;
      }

      context.lines.push(`REPEAT ${count}`);
      context.tap(button, 2);
      context.lines.push('END');
    },

    wait: (ms) => context.lines.push(`WAIT ${ms}ms`),

    down: (button) => {
      context.lines.push(`DOWN ${button}`);
      context.wait(delay);
    },

    up: (button) => {
      context.lines.push(`UP ${button}`);
      context.wait(delay);
    },

    initColorPanel: () => {
      context.lines.push('# --- 初始化调色板面板 ---');

      context.tap('Y');
      context.tapMultiple('DPAD_DOWN', 10);
      context.tapMultiple('DPAD_UP', 8);
      context.tap('Y');
      context.tap('R');
      context.tap('R');
      context.tap('R');
      context.wait(100);
      context.tap('A');

      context.curColorPanelIdx = 0;
    },

    chooseColorPanel: (idx) => {
      if (context.curColorPanelIdx === idx) {
        return;
      }

      context.tap('Y');

      if (idx > context.curColorPanelIdx) {
        context.tapMultiple('DPAD_DOWN', idx - context.curColorPanelIdx);
      } else {
        context.tapMultiple('DPAD_UP', context.curColorPanelIdx - idx);
      }

      context.curColorPanelIdx = idx;
      context.tap('A');
    },

    resetHSVColorPanel: () => {
      context.lines.push('# --- 复位 HSV 调色板 ---');

      context.wait(100);
      context.lines.push('STICK LEFT_STICK -100 +100');
      context.wait(100);
      context.lines.push('DOWN ZL');
      context.wait(5000);
      context.lines.push('UP ZL');
      context.wait(100);
      context.lines.push('RESET_STICK LEFT_STICK');
      context.wait(100);
    },

    chooseHSVColor: (slotIdx, colorIdx) => {
      const color = context.palette[colorIdx - 1];

      if (!color) {
        return;
      }

      const hsv = rgbToTomodachiHSV(
        color.r,
        color.g,
        color.b
      );

      context.lines.push(
        `\n# 配置色槽 Slot ${slotIdx} <- ` +
        `调色板颜色 ${colorIdx}: ` +
        `RGB(${color.r},${color.g},${color.b})`
      );

      context.wait(100);
      context.chooseColorPanel(slotIdx);
      context.wait(100);
      context.tap('Y');
      context.wait(100);
      context.tap('Y');
      context.wait(100);
      context.resetHSVColorPanel();
      context.wait(100);
      context.tapMultiple('ZR', hsv.hTicks);
      context.wait(100);
      context.tapMultiple('DPAD_RIGHT', hsv.sTicks);
      context.wait(100);
      context.tapMultiple('DPAD_DOWN', hsv.vTicks);
      context.wait(100);
      context.tap('A');
      context.wait(100);
    },

    moveTo: (targetX, targetY) => {
      const dx = targetX - context.curX;
      const dy = targetY - context.curY;

      if (dx > 0) {
        context.tapMultiple('DPAD_RIGHT', dx);
      } else if (dx < 0) {
        context.tapMultiple('DPAD_LEFT', -dx);
      }

      if (dy > 0) {
        context.tapMultiple('DPAD_DOWN', dy);
      } else if (dy < 0) {
        context.tapMultiple('DPAD_UP', -dy);
      }

      context.curX = targetX;
      context.curY = targetY;
    },

    getId: (x, y) => y * w + x,

    manhattanDistance: (a, b) => Math.abs(a.x - b.x) + Math.abs(a.y - b.y),

    directionFromTo: (from, to) => {
      const dx = to.x - from.x;
      const dy = to.y - from.y;

      if (dx === 1 && dy === 0) return 'DPAD_RIGHT';
      if (dx === -1 && dy === 0) return 'DPAD_LEFT';
      if (dx === 0 && dy === 1) return 'DPAD_DOWN';
      if (dx === 0 && dy === -1) return 'DPAD_UP';

      throw new Error(
        `Invalid adjacent move: (${from.x},${from.y}) -> (${to.x},${to.y})`
      );
    },
  };

  return context;
};

export const generateZigMacroScriptBySegment = (
  w: number,
  h: number,
  palette: RGBColor[],
  pIndices: (number | null)[][],
  delay: number
): string => {
  type Segment = {
    a: Point;
    b: Point;
    length: number;
  };

  type ComponentPlan = {
    segments: Segment[];
  };

  const context = createZigMacroScriptContext(w, h, palette, pIndices, delay);

  const {
    lines,
    tap,
    tapMultiple,
    down,
    up,
    initColorPanel,
    chooseColorPanel,
    chooseHSVColor,
    moveTo,
    directionFromTo,
    manhattanDistance,
    getId,
  } = context;

  const cellId = getId;
  const manhattan = manhattanDistance;

  lines.push('# ==========================================');
  lines.push('# Tomodachi Life 自动化绘制宏脚本');
  lines.push('# 优化策略:');
  lines.push('# 1. 同色像素批量绘制，避免频繁切换色槽');
  lines.push('# 2. 连续像素使用 A 按住 + 方向移动');
  lines.push('# 3. A 按住时只经过同色像素，避免串色');
  lines.push('# 4. 水平/垂直线段自动选择较优方向');
  lines.push('# 5. 相邻线段尽量保持 A 按下状态连续绘制');
  lines.push(`# 尺寸: ${w}x${h} | 颜色数: ${palette.length} | 延迟: ${delay}ms`);
  lines.push('# ==========================================\n');

  // ------------------------------------------------------------
  // 根据一组像素生成最大水平/垂直连续线段
  // ------------------------------------------------------------

  const buildSegments = (
    points: Point[],
    orientation: 'H' | 'V'
  ): Segment[] => {
    const pointSet = new Set<number>();

    for (const p of points) {
      pointSet.add(cellId(p.x, p.y));
    }

    const segments: Segment[] = [];

    if (orientation === 'H') {
      for (const p of points) {
        // 左边有同色像素，不是线段起点
        if (
          p.x > 0 &&
          pointSet.has(cellId(p.x - 1, p.y))
        ) {
          continue;
        }

        let endX = p.x;

        while (
          endX + 1 < w &&
          pointSet.has(cellId(endX + 1, p.y))
        ) {
          endX++;
        }

        segments.push({
          a: { x: p.x, y: p.y },
          b: { x: endX, y: p.y },
          length: endX - p.x + 1,
        });
      }
    } else {
      for (const p of points) {
        // 上边有同色像素，不是线段起点
        if (
          p.y > 0 &&
          pointSet.has(cellId(p.x, p.y - 1))
        ) {
          continue;
        }

        let endY = p.y;

        while (
          endY + 1 < h &&
          pointSet.has(cellId(p.x, endY + 1))
        ) {
          endY++;
        }

        segments.push({
          a: { x: p.x, y: p.y },
          b: { x: p.x, y: endY },
          length: endY - p.y + 1,
        });
      }
    }

    return segments;
  };

  // ------------------------------------------------------------
  // 找出某个颜色的所有 4 邻接连通块
  // ------------------------------------------------------------

  const buildColorComponents = (
    colorIndex: number
  ): ComponentPlan[] => {
    const targetId = colorIndex - 1;

    const unvisited = new Set<number>();

    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        if (pIndices[y]?.[x] === targetId) {
          unvisited.add(cellId(x, y));
        }
      }
    }

    const components: ComponentPlan[] = [];

    const dirs = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ] as const;

    while (unvisited.size > 0) {
      const iterator = unvisited.values();
      const startId = iterator.next().value as number;

      unvisited.delete(startId);

      const queue: number[] = [startId];
      const points: Point[] = [];

      for (let qi = 0; qi < queue.length; qi++) {
        const id = queue[qi];

        const x = id % w;
        const y = Math.floor(id / w);

        points.push({ x, y });

        for (const [dx, dy] of dirs) {
          const nx = x + dx;
          const ny = y + dy;

          if (
            nx < 0 ||
            nx >= w ||
            ny < 0 ||
            ny >= h
          ) {
            continue;
          }

          const nid = cellId(nx, ny);

          if (unvisited.has(nid)) {
            unvisited.delete(nid);
            queue.push(nid);
          }
        }
      }

      // --------------------------------------------------------
      // 同一个连通块同时尝试：
      //   H = 水平扫描
      //   V = 垂直扫描
      //
      // 哪个线段数量更少就用哪个。
      // --------------------------------------------------------

      const horizontal = buildSegments(points, 'H');
      const vertical = buildSegments(points, 'V');

      const segments =
        horizontal.length <= vertical.length
          ? horizontal
          : vertical;

      components.push({
        segments,
      });
    }

    return components;
  };

  // ------------------------------------------------------------
  // 在一组线段中找到离当前位置最近的入口端
  // ------------------------------------------------------------

  const findNearestSegment = (
    segments: Segment[],
    x: number,
    y: number,
    used?: boolean[]
  ): {
    index: number;
    start: Point;
    distance: number;
  } => {
    let bestIndex = -1;
    let bestStart: Point | null = null;
    let bestDistance = Infinity;
    let bestLength = -1;

    const current: Point = { x, y };

    for (let i = 0; i < segments.length; i++) {
      if (used && used[i]) {
        continue;
      }

      const seg = segments[i];

      const distA = manhattan(current, seg.a);
      const distB = manhattan(current, seg.b);

      let start: Point;
      let dist: number;

      if (distA <= distB) {
        start = seg.a;
        dist = distA;
      } else {
        start = seg.b;
        dist = distB;
      }

      // 距离相同时，优先较长线段
      if (
        dist < bestDistance ||
        (
          dist === bestDistance &&
          seg.length > bestLength
        )
      ) {
        bestDistance = dist;
        bestIndex = i;
        bestStart = start;
        bestLength = seg.length;
      }
    }

    if (!bestStart) {
      throw new Error('No available segment found');
    }

    return {
      index: bestIndex,
      start: bestStart,
      distance: bestDistance,
    };
  };

  // ------------------------------------------------------------
  // A 已经按住：
  // 将一个完整线段绘制出来
  // ------------------------------------------------------------

  const drawSegmentHeld = (
    seg: Segment,
    start: Point
  ) => {
    const isStartA =
      start.x === seg.a.x &&
      start.y === seg.a.y;

    const end = isStartA
      ? seg.b
      : seg.a;

    const dx = end.x - start.x;
    const dy = end.y - start.y;

    // 单点线段，不需要移动
    if (dx === 0 && dy === 0) {
      context.curX = end.x;
      context.curY = end.y;
      return;
    }

    // 水平线段
    if (dy === 0) {
      if (dx > 0) {
        tapMultiple('DPAD_RIGHT', dx);
      } else {
        tapMultiple('DPAD_LEFT', -dx);
      }
    }
    // 垂直线段
    else if (dx === 0) {
      if (dy > 0) {
        tapMultiple('DPAD_DOWN', dy);
      } else {
        tapMultiple('DPAD_UP', -dy);
      }
    }
    // 理论上 buildSegments() 不可能产生斜线
    else {
      throw new Error(
        `Invalid segment: (${start.x},${start.y}) -> ` +
        `(${end.x},${end.y})`
      );
    }

    context.curX = end.x;
    context.curY = end.y;
  };

  // ------------------------------------------------------------
  // A 已经按住：
  // 移动 1 格进入相邻线段
  // ------------------------------------------------------------

  const moveHeldOneStep = (
    target: Point
  ) => {
    const current: Point = {
      x: context.curX,
      y: context.curY,
    };

    if (
      manhattan(current, target) !== 1
    ) {
      throw new Error(
        `moveHeldOneStep requires adjacent point: ` +
        `(${context.curX},${context.curY}) -> (${target.x},${target.y})`
      );
    }

    const direction = directionFromTo(
      current,
      target
    );

    tap(direction);

    context.curX = target.x;
    context.curY = target.y;
  };

  // ------------------------------------------------------------
  // 绘制一个颜色连通块
  //
  // 关键逻辑：
  //
  // DOWN A
  //    ├─ 连续同色线段移动
  //    ├─ 如果另一条线段端点与当前位置相邻
  //    │    └─ 继续保持 A 按下
  //    └─ 如果不相邻
  //         └─ UP A
  //             移动到下一条线段
  //             DOWN A
  //
  // 因此 A 永远不会经过空白/其它颜色。
  // ------------------------------------------------------------

  const drawComponent = (
    component: ComponentPlan
  ) => {
    const segments = component.segments;

    if (segments.length === 0) {
      return;
    }

    const used = new Array<boolean>(
      segments.length
    ).fill(false);

    // endpoint -> segment index
    const endpointToSegment =
      new Map<number, number>();

    for (let i = 0; i < segments.length; i++) {
      const seg = segments[i];

      endpointToSegment.set(
        cellId(seg.a.x, seg.a.y),
        i
      );

      endpointToSegment.set(
        cellId(seg.b.x, seg.b.y),
        i
      );
    }

    let remaining = segments.length;

    // ----------------------------------------------------------
    // 找当前点周围是否存在：
    // "某条未绘制线段的端点"
    //
    // 如果存在，就可以继续保持 A。
    // ----------------------------------------------------------

    const findAdjacentUnusedSegment = (): number => {
      const candidates: number[] = [];

      const dirs = [
        [1, 0],
        [-1, 0],
        [0, 1],
        [0, -1],
      ] as const;

      for (const [dx, dy] of dirs) {
        const nx = context.curX + dx;
        const ny = context.curY + dy;

        if (
          nx < 0 ||
          nx >= w ||
          ny < 0 ||
          ny >= h
        ) {
          continue;
        }

        const idx =
          endpointToSegment.get(
            cellId(nx, ny)
          );

        if (
          idx !== undefined &&
          !used[idx]
        ) {
          candidates.push(idx);
        }
      }

      if (candidates.length === 0) {
        return -1;
      }

      // 有多个可选时，优先最长的
      candidates.sort(
        (a, b) =>
          segments[b].length -
          segments[a].length
      );

      return candidates[0];
    };

    // ----------------------------------------------------------
    // 一个新的 A-held stroke
    // ----------------------------------------------------------

    const startNewStroke = (
      segmentIndex: number,
      start: Point
    ) => {
      const seg = segments[segmentIndex];

      moveTo(start.x, start.y);

      down('A');

      drawSegmentHeld(
        seg,
        start
      );

      used[segmentIndex] = true;
      remaining--;
    };

    // ----------------------------------------------------------
    // 连续处理这个 Component
    // ----------------------------------------------------------

    while (remaining > 0) {
      // --------------------------------------------------------
      // 如果当前已经在某条线段末端附近，优先无缝接下一条。
      // --------------------------------------------------------

      const adjacentIndex =
        findAdjacentUnusedSegment();

      if (adjacentIndex >= 0) {
        const seg =
          segments[adjacentIndex];

        const distA =
          manhattan(
            { x: context.curX, y: context.curY },
            seg.a
          );

        const start =
          distA === 1
            ? seg.a
            : seg.b;

        // 当前 A 仍然保持按下
        moveHeldOneStep(start);

        drawSegmentHeld(
          seg,
          start
        );

        used[adjacentIndex] = true;
        remaining--;

        continue;
      }

      // --------------------------------------------------------
      // 找不到相邻线段：
      // 说明下一条线段无法在不经过其它颜色的情况下直接接上。
      //
      // 所以必须松 A。
      // --------------------------------------------------------

      if (
        // 当前尚未开始任何 stroke
        !used.some(v => v)
      ) {
        const nearest =
          findNearestSegment(
            segments,
            context.curX,
            context.curY,
            used
          );

        startNewStroke(
          nearest.index,
          nearest.start
        );

        continue;
      }

      // 已经有绘制内容，现在准备开始下一条分离线段
      up('A');

      const nearest =
        findNearestSegment(
          segments,
          context.curX,
          context.curY,
          used
        );

      startNewStroke(
        nearest.index,
        nearest.start
      );
    }

    // 当前 stroke 最后收尾
    up('A');
  };

  // ------------------------------------------------------------
  // 计算一个颜色所有连通块中距离当前光标最近的位置
  // ------------------------------------------------------------

  const getNearestDistanceToColor = (
    components: ComponentPlan[]
  ): number => {
    let best = Infinity;

    for (const component of components) {
      for (const seg of component.segments) {
        best = Math.min(
          best,
          manhattan(
            { x: context.curX, y: context.curY },
            seg.a
          ),
          manhattan(
            { x: context.curX, y: context.curY },
            seg.b
          )
        );
      }
    }

    return best;
  };

  // ------------------------------------------------------------
  // 绘制一个颜色的所有连通块
  // 连通块之间一定 UP A 后移动
  // ------------------------------------------------------------

  const drawColor = (
    colorIndex: number,
    components: ComponentPlan[]
  ) => {
    lines.push(
      `\n# --- 开始绘制颜色 ${colorIndex} ---`
    );

    const remainingComponents =
      new Set<ComponentPlan>(
        components
      );

    while (
      remainingComponents.size > 0
    ) {
      let bestComponent:
        | ComponentPlan
        | null = null;

      let bestDistance = Infinity;

      for (
        const component
        of remainingComponents
      ) {
        let distance = Infinity;

        for (
          const seg
          of component.segments
        ) {
          distance = Math.min(
            distance,
            manhattan(
              { x: context.curX, y: context.curY },
              seg.a
            ),
            manhattan(
              { x: context.curX, y: context.curY },
              seg.b
            )
          );
        }

        if (
          distance < bestDistance
        ) {
          bestDistance = distance;
          bestComponent = component;
        }
      }

      if (!bestComponent) {
        break;
      }

      drawComponent(
        bestComponent
      );

      remainingComponents.delete(
        bestComponent
      );
    }

    lines.push(
      `# --- 颜色 ${colorIndex} 绘制完成 ---`
    );
  };

  // ============================================================
  // 开始
  // ============================================================

  initColorPanel();

  const colorSize =
    palette.length + 1;

  let colorBatchStart = 1;

  while (
    colorBatchStart < colorSize
  ) {
    const colorBatchEnd =
      Math.min(
        colorBatchStart + 8,
        colorSize - 1
      );

    lines.push(`
# ==========================================
# 绘制批次: 颜色 ${colorBatchStart} ~ ${colorBatchEnd}
# ==========================================`
    );

    // ----------------------------------------------------------
    // 先建立这个 Batch 内每种颜色的连通块。
    //
    // 这样可以：
    // 1. 跳过完全不存在的颜色
    // 2. 后面一个颜色只配置一次
    // ----------------------------------------------------------

    const colorPlans =
      new Map<
        number,
        ComponentPlan[]
      >();

    for (
      let colorIndex = colorBatchStart;
      colorIndex <= colorBatchEnd;
      colorIndex++
    ) {
      const components =
        buildColorComponents(
          colorIndex
        );

      if (components.length > 0) {
        colorPlans.set(
          colorIndex,
          components
        );
      }
    }

    // ----------------------------------------------------------
    // 当前 Batch 没有任何像素
    // ----------------------------------------------------------

    if (colorPlans.size === 0) {
      colorBatchStart += 9;
      continue;
    }

    // ----------------------------------------------------------
    // 只配置真正用得到的颜色
    //
    // 旧版是固定配置 9 个 Slot。
    // 新版只有有实际像素的 Slot 才配置。
    // ----------------------------------------------------------

    const presentColors =
      Array.from(
        colorPlans.keys()
      ).sort(
        (a, b) => a - b
      );

    for (
      const colorIndex
      of presentColors
    ) {
      const slot =
        colorIndex -
        colorBatchStart;

      chooseHSVColor(
        slot,
        colorIndex
      );
    }

    // ----------------------------------------------------------
    // 接下来决定颜色绘制顺序。
    //
    // 不再严格按照 1,2,3... 顺序。
    //
    // 每次选择离当前绘图光标最近的颜色，
    // 减少不同颜色之间的无效移动。
    // ----------------------------------------------------------

    const remainingColors =
      new Set<number>(
        presentColors
      );

    while (
      remainingColors.size > 0
    ) {
      let bestColor = -1;
      let bestDistance = Infinity;

      for (
        const colorIndex
        of remainingColors
      ) {
        const components =
          colorPlans.get(
            colorIndex
          )!;

        const distance =
          getNearestDistanceToColor(
            components
          );

        if (
          distance < bestDistance
        ) {
          bestDistance =
            distance;
          bestColor =
            colorIndex;
        }
      }

      if (bestColor < 0) {
        break;
      }

      const slot =
        bestColor -
        colorBatchStart;

      lines.push(`
# ==========================================
# 绘制颜色 ${bestColor} (Slot ${slot})
# ==========================================`
      );

      // 只在真正切换颜色时调用
      chooseColorPanel(slot);

      drawColor(
        bestColor,
        colorPlans.get(bestColor)!
      );

      remainingColors.delete(
        bestColor
      );
    }

    colorBatchStart += 9;
  }

  // ------------------------------------------------------------
  // 全部完成，光标返回 0,0
  // ------------------------------------------------------------

  lines.push(`
# ==========================================
# 全图绘制完成，复位光标至 (0,0)
# ==========================================`
  );

  moveTo(0, 0);

  return lines.join('\n');
};

export const generateZigMacroScriptDFS = (
  w: number,
  h: number,
  palette: RGBColor[],
  pIndices: (number | null)[][],
  delay: number
): string => {
  type Component = {
    pixels: Point[];
  };

  type DfsTree = {
    parent: Int32Array;
    depth: Int32Array;
    deepest: number;
  };

  const context = createZigMacroScriptContext(w, h, palette, pIndices, delay);

  const {
    lines,
    tap,
    down,
    up,
    initColorPanel,
    chooseColorPanel,
    chooseHSVColor,
    moveTo,
    getId,
    manhattanDistance,
  } = context;

  // lines.push('# ==========================================');
  // lines.push('# Tomodachi Life 自动化绘制宏脚本');
  // lines.push('#');
  // lines.push('# DFS 路径优化策略：');
  // lines.push('# 1. 一次扫描整张图，建立每种颜色的 4 邻接连通块');
  // lines.push('# 2. 一个颜色连通块只绘制一次，完成后才进入下一个连通块');
  // lines.push('# 3. 连通块内先建立 DFS 生成树，再执行“开放式 DFS”');
  // lines.push('# 4. 最终路径上的树边只走一次，其余树边走两次');
  // lines.push('# 5. 因此连通块移动步数从固定的 2(N-1) 降为 2(N-1)-D');
  // lines.push('#    其中 D 是 DFS 生成树中入口到最深节点的深度');
  // lines.push('# 6. 使用低可用度优先（Warnsdorff 风格）尝试多种方向顺序，尽量让 D 更大');
  // lines.push('# 7. A 按下期间始终只在当前连通块内移动');
  // lines.push('# 8. 连通块之间仍然 UP A 后再移动');
  // lines.push(`# 尺寸: ${w}x${h} | 颜色数: ${palette.length} | 延迟: ${delay}ms`);
  // lines.push('# ==========================================');
  // lines.push('');

  lines.push('# ==========================================');
  lines.push('# Tomodachi Life 自动化绘制宏脚本');
  lines.push('#');
  lines.push('# DFS 路径优化策略：');
  lines.push('# 1. 扫描各个颜色的所有连通块');
  lines.push('# 2. 一次性将一种颜色的所有连通块绘制完成, 之后再绘制下一个颜色');
  lines.push(`# 尺寸: ${w}x${h} | 颜色数: ${palette.length} | 延迟: ${delay}ms`);
  lines.push('# ==========================================');
  lines.push('');

  // ============================================================
  // 四方向
  // ============================================================

  const directions = [
    { dx: 1, dy: 0, button: 'DPAD_RIGHT' },
    { dx: 0, dy: 1, button: 'DPAD_DOWN' },
    { dx: -1, dy: 0, button: 'DPAD_LEFT' },
    { dx: 0, dy: -1, button: 'DPAD_UP' },
  ] as const;

  // ============================================================
  // 一次性建立整个图像的所有颜色连通块
  // ============================================================

  const buildAllColorComponents = (): Map<number, Component[]> => {
    const componentsByColor = new Map<number, Component[]>();
    const visited = new Uint8Array(w * h);

    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const pixelIdx = pIndices[y]?.[x];

        if (pixelIdx === undefined || pixelIdx === null) {
          continue;
        }

        const startId = getId(x, y);
        if (visited[startId]) {
          continue;
        }

        const colorIndex = pixelIdx + 1;
        const componentPixels: Point[] = [];
        const queue: Point[] = [{ x, y }];
        visited[startId] = 1;

        let queueIndex = 0;
        while (queueIndex < queue.length) {
          const current = queue[queueIndex++];
          componentPixels.push(current);

          for (const dir of directions) {
            const nx = current.x + dir.dx;
            const ny = current.y + dir.dy;

            if (nx < 0 || nx >= w || ny < 0 || ny >= h) {
              continue;
            }

            const neighborId = getId(nx, ny);
            if (visited[neighborId]) {
              continue;
            }

            if (pIndices[ny]?.[nx] !== pixelIdx) {
              continue;
            }

            visited[neighborId] = 1;
            queue.push({ x: nx, y: ny });
          }
        }

        const component: Component = { pixels: componentPixels };
        const list = componentsByColor.get(colorIndex);

        if (list) {
          list.push(component);
        } else {
          componentsByColor.set(colorIndex, [component]);
        }
      }
    }

    return componentsByColor;
  };

  // ============================================================
  // 找到当前光标 -> Component 中最近的像素
  // ============================================================

  const findNearestEntryPoint = (
    component: Component
  ): { point: Point; distance: number } => {
    let bestPoint = component.pixels[0];
    let bestDistance = manhattanDistance(
      { x: context.curX, y: context.curY },
      bestPoint
    );

    for (let i = 1; i < component.pixels.length; i++) {
      const point = component.pixels[i];
      const distance = manhattanDistance(
        { x: context.curX, y: context.curY },
        point
      );

      if (distance < bestDistance) {
        bestDistance = distance;
        bestPoint = point;
      }
    }

    return {
      point: bestPoint,
      distance: bestDistance,
    };
  };

  // ============================================================
  // 为 Component 构建 DFS 生成树
  //
  // 关键优化：
  // 旧版 DFS 在完成全部分支后，必须沿树边全部回到 root。
  // 新版先建立树，再让“最深叶子”作为最终终点。
  // 这样 root -> deepest 这条路径上的边只需要走一次。
  //
  // 同一个 Component 尝试多个 DFS 邻居优先级：
  //   1. 低 onward-degree 优先（更容易形成长主路径）
  //   2. 高 onward-degree 作为另一组候选
  //   3. 四个方向分别轮换作为 tie-break
  // ============================================================

  const buildDfsTree = (
    neighbors: number[][],
    neighborDirs: number[][],
    startLocal: number,
    preferLowOnward: boolean,
    directionOffset: number
  ): DfsTree => {
    const n = neighbors.length;

    const parent = new Int32Array(n);
    parent.fill(-2);

    const depth = new Int32Array(n);
    const visited = new Uint8Array(n);

    visited[startLocal] = 1;
    parent[startLocal] = -1;
    depth[startLocal] = 0;

    const stack: number[] = [startLocal];
    let deepest = startLocal;

    while (stack.length > 0) {
      const current = stack[stack.length - 1];
      const currentNeighbors = neighbors[current];
      const currentDirs = neighborDirs[current];

      let bestLocal = -1;
      let bestOnward = preferLowOnward ? Infinity : -Infinity;
      let bestDegree = Infinity;
      let bestDirRank = Infinity;

      for (let i = 0; i < currentNeighbors.length; i++) {
        const neighbor = currentNeighbors[i];
        if (visited[neighbor]) {
          continue;
        }

        let onward = 0;
        const nextNeighbors = neighbors[neighbor];

        for (const next of nextNeighbors) {
          if (!visited[next]) {
            onward++;
          }
        }

        const degree = nextNeighbors.length;
        const dirRank =
          (currentDirs[i] - directionOffset + directions.length) %
          directions.length;

        const betterOnward = preferLowOnward
          ? onward < bestOnward
          : onward > bestOnward;

        const sameOnward = onward === bestOnward;
        const betterDegree = sameOnward && degree < bestDegree;
        const sameDegree = sameOnward && degree === bestDegree;
        const betterDir = sameDegree && dirRank < bestDirRank;

        if (
          bestLocal < 0 ||
          betterOnward ||
          betterDegree ||
          betterDir
        ) {
          bestLocal = neighbor;
          bestOnward = onward;
          bestDegree = degree;
          bestDirRank = dirRank;
        }
      }

      if (bestLocal < 0) {
        stack.pop();
        continue;
      }

      const next = bestLocal;
      visited[next] = 1;
      parent[next] = current;
      depth[next] = depth[current] + 1;

      if (depth[next] > depth[deepest]) {
        deepest = next;
      }

      stack.push(next);
    }

    // Component 已经在前面的 BFS 阶段确认连通，所以 DFS 树必须覆盖全部像素。
    for (let i = 0; i < n; i++) {
      if (!visited[i]) {
        throw new Error(
          `DFS tree incomplete: visited=${visited.reduce((sum, v) => sum + v, 0)}, expected=${n}`
        );
      }
    }

    return {
      parent,
      depth,
      deepest,
    };
  };

  // ============================================================
  // 在多个 DFS 树中选一个：
  // 最大化 root -> deepest 的深度。
  //
  // 对宏执行时间而言：
  // moves = 2 * (N - 1) - depth(deepest)
  // 所以只要 depth 更大，宏移动次数就一定更少。
  // ============================================================

  const buildBestDfsTree = (
    component: Component,
    start: Point
  ): { tree: DfsTree; startLocal: number } => {
    const n = component.pixels.length;
    const indexById = new Map<number, number>();

    for (let i = 0; i < n; i++) {
      const point = component.pixels[i];
      indexById.set(getId(point.x, point.y), i);
    }

    const startLocal = indexById.get(getId(start.x, start.y));
    if (startLocal === undefined) {
      throw new Error(
        `Invalid DFS start point: (${start.x},${start.y})`
      );
    }

    // 只建立一次 Component 邻接表；8 种 DFS 策略共享这份结构。
    const neighbors: number[][] = Array.from(
      { length: n },
      () => []
    );
    const neighborDirs: number[][] = Array.from(
      { length: n },
      () => []
    );

    for (let i = 0; i < n; i++) {
      const point = component.pixels[i];

      for (let dirIndex = 0; dirIndex < directions.length; dirIndex++) {
        const dir = directions[dirIndex];
        const nx = point.x + dir.dx;
        const ny = point.y + dir.dy;

        if (nx < 0 || nx >= w || ny < 0 || ny >= h) {
          continue;
        }

        const neighborLocal = indexById.get(getId(nx, ny));
        if (neighborLocal === undefined) {
          continue;
        }

        neighbors[i].push(neighborLocal);
        neighborDirs[i].push(dirIndex);
      }
    }

    let bestTree: DfsTree | null = null;
    let bestDepth = -1;

    for (const preferLowOnward of [true, false]) {
      for (let directionOffset = 0; directionOffset < directions.length; directionOffset++) {
        const tree = buildDfsTree(
          neighbors,
          neighborDirs,
          startLocal,
          preferLowOnward,
          directionOffset
        );

        const candidateDepth = tree.depth[tree.deepest];
        if (candidateDepth > bestDepth) {
          bestDepth = candidateDepth;
          bestTree = tree;
        }
      }
    }

    if (!bestTree) {
      throw new Error('Failed to build optimized DFS tree');
    }

    return {
      tree: bestTree,
      startLocal,
    };
  };

  // ============================================================
  // 用一个一步移动函数输出宏。
  // 这里所有调用的两个节点都是同一 Component 内的相邻像素。
  // ============================================================

  const moveOnePoint = (from: Point, to: Point) => {
    const dx = to.x - from.x;
    const dy = to.y - from.y;

    if (dx === 1 && dy === 0) {
      tap('DPAD_RIGHT');
    } else if (dx === -1 && dy === 0) {
      tap('DPAD_LEFT');
    } else if (dx === 0 && dy === 1) {
      tap('DPAD_DOWN');
    } else if (dx === 0 && dy === -1) {
      tap('DPAD_UP');
    } else {
      throw new Error(
        `Invalid adjacent move: (${from.x},${from.y}) -> (${to.x},${to.y})`
      );
    }

    context.curX = to.x;
    context.curY = to.y;
  };

  // ============================================================
  // 对一棵以 finalPath 为“主干”的树做开放式 DFS：
  //
  // 主干上的边：只走一次
  // 非主干边：进入 + 返回，共两次
  //
  // 因此总移动数严格等于：
  //   2(N-1) - |finalPath edges|
  // ============================================================

  const drawComponentWithOptimizedDFS = (
    component: Component,
    start: Point
  ) => {
    if (component.pixels.length === 0) {
      return;
    }

    const { tree, startLocal } = buildBestDfsTree(
      component,
      start
    );

    const n = component.pixels.length;
    const deepest = tree.deepest;

    // ----------------------------------------------------------
    // 从 deepest 沿 parent 回到 start，得到最终只走一次的主干。
    // ----------------------------------------------------------

    const finalPath: number[] = [];
    for (let current = deepest; current !== -1; current = tree.parent[current]) {
      finalPath.push(current);
    }
    finalPath.reverse();

    if (
      finalPath.length === 0 ||
      finalPath[0] !== startLocal ||
      finalPath[finalPath.length - 1] !== deepest
    ) {
      throw new Error('Invalid optimized DFS final path');
    }

    const onFinalPath = new Uint8Array(n);
    for (const local of finalPath) {
      onFinalPath[local] = 1;
    }

    // ----------------------------------------------------------
    // 用 firstChild / nextSibling 存储树，避免 children[][] 的大量对象。
    // ----------------------------------------------------------

    const firstChild = new Int32Array(n);
    const nextSibling = new Int32Array(n);
    firstChild.fill(-1);
    nextSibling.fill(-1);

    for (let local = 0; local < n; local++) {
      const parent = tree.parent[local];
      if (parent < 0) {
        continue;
      }

      nextSibling[local] = firstChild[parent];
      firstChild[parent] = local;
    }

    const moveLocal = (fromLocal: number, toLocal: number) => {
      moveOnePoint(
        component.pixels[fromLocal],
        component.pixels[toLocal]
      );
    };

    // ----------------------------------------------------------
    // DFS 闭合遍历一个“非主干子树”。
    //
    // 进入 root 后，把整个子树走完，再返回 root 的 parent。
    // 因为 root 不在 finalPath，这部分所有树边必须走两次。
    // ----------------------------------------------------------

    const walkClosedSubtree = (root: number) => {
      const parentOfRoot = tree.parent[root];
      if (parentOfRoot < 0) {
        throw new Error('Closed subtree root cannot be the DFS root');
      }

      moveLocal(parentOfRoot, root);

      const nodeStack: number[] = [root];
      const childStack: number[] = [firstChild[root]];

      while (nodeStack.length > 0) {
        const top = nodeStack.length - 1;
        const current = nodeStack[top];
        const child = childStack[top];

        if (child >= 0) {
          childStack[top] = nextSibling[child];
          moveLocal(current, child);
          nodeStack.push(child);
          childStack.push(firstChild[child]);
          continue;
        }

        nodeStack.pop();
        childStack.pop();

        const parent = tree.parent[current];
        if (parent < 0) {
          throw new Error('Broken DFS tree during closed traversal');
        }

        moveLocal(current, parent);
      }
    };

    // ----------------------------------------------------------
    // DOWN A：开始绘制当前连通块。
    // ----------------------------------------------------------

    down('A');

    // ----------------------------------------------------------
    // 沿 finalPath 一直向前：
    // 每到一个主干节点，先把挂在它上面的非主干子树全部闭合走完，
    // 然后只用一步进入下一个主干节点。
    // ----------------------------------------------------------

    for (let pathIndex = 0; pathIndex < finalPath.length; pathIndex++) {
      const current = finalPath[pathIndex];

      for (
        let child = firstChild[current];
        child >= 0;
        child = nextSibling[child]
      ) {
        if (onFinalPath[child]) {
          continue;
        }

        walkClosedSubtree(child);
      }

      if (pathIndex + 1 < finalPath.length) {
        moveLocal(current, finalPath[pathIndex + 1]);
      }
    }

    // ----------------------------------------------------------
    // 安全检查：
    // 一个 DFS 生成树共 N-1 条边，finalPath 有 D 条边只走一次，
    // 其余边走两次，所以总移动应该精确等于 2(N-1)-D。
    // ----------------------------------------------------------

    // tap 计数无法直接从 context 获取，因此只验证结构：
    // 最深节点存在且 finalPath 覆盖 root -> deepest。
    if (finalPath.length !== tree.depth[deepest] + 1) {
      up('A');
      throw new Error(
        `Optimized DFS path mismatch: ` +
        `path=${finalPath.length}, depth=${tree.depth[deepest]}`
      );
    }

    up('A');

    context.curX = component.pixels[deepest].x;
    context.curY = component.pixels[deepest].y;

  };

  // ============================================================
  // 绘制一种颜色的全部 Component
  //
  // Component 之间一定 UP A 后移动。
  // 仍然采用当前光标最近 Component 的贪心顺序，
  // 但每个 Component 内部不再强制回到入口点。
  // ============================================================

  const drawColorComponents = (
    colorIndex: number,
    components: Component[]
  ) => {
    if (components.length === 0) {
      return;
    }

    lines.push('');
    lines.push('# ==========================================');
    lines.push(`# 开始绘制颜色 ${colorIndex}`);
    lines.push(`# 连通块数量: ${components.length}`);
    lines.push('# ==========================================');

    const remaining = new Set<Component>(components);

    while (remaining.size > 0) {
      let bestComponent: Component | null = null;
      let bestEntry: Point | null = null;
      let bestDistance = Infinity;

      for (const component of remaining) {
        const result = findNearestEntryPoint(component);

        if (result.distance < bestDistance) {
          bestDistance = result.distance;
          bestComponent = component;
          bestEntry = result.point;
        }
      }

      if (!bestComponent || !bestEntry) {
        throw new Error(
          `Failed to find next component for color ${colorIndex}`
        );
      }

      // A 必须保持 UP，连通块之间可以安全地自由移动。
      moveTo(bestEntry.x, bestEntry.y);

      // 一个 Component：一次 DOWN A，所有像素完成后才 UP A。
      drawComponentWithOptimizedDFS(bestComponent, bestEntry);

      remaining.delete(bestComponent);
    }

    lines.push(`# 颜色 ${colorIndex} 全部连通块绘制完成`);
  };

  // ============================================================
  // 开始建立所有颜色的 Component
  // ============================================================

  const componentsByColor = buildAllColorComponents();

  initColorPanel();

  const colorSize = palette.length + 1;

  // ============================================================
  // 按原来的 9 色一批处理
  // ============================================================

  let colorBatchStart = 1;

  while (colorBatchStart < colorSize) {
    const colorBatchEnd = Math.min(
      colorBatchStart + 8,
      colorSize - 1
    );

    lines.push('');
    lines.push('# ==========================================');
    lines.push(
      `# 绘制批次: 颜色 ${colorBatchStart} ~ ${colorBatchEnd}`
    );
    lines.push('# ==========================================');

    const presentColors: number[] = [];

    for (
      let colorIndex = colorBatchStart;
      colorIndex <= colorBatchEnd;
      colorIndex++
    ) {
      const components = componentsByColor.get(colorIndex);

      if (components && components.length > 0) {
        presentColors.push(colorIndex);
      }
    }

    if (presentColors.length === 0) {
      colorBatchStart += 9;
      continue;
    }

    // 只配置真正存在的颜色。
    for (const colorIndex of presentColors) {
      const slot = colorIndex - colorBatchStart;
      chooseHSVColor(slot, colorIndex);
    }

    // 保持原有颜色 Index 顺序，避免引入额外的颜色级别行为变化。
    for (const colorIndex of presentColors) {
      const components = componentsByColor.get(colorIndex);

      if (!components || components.length === 0) {
        continue;
      }

      const slot = colorIndex - colorBatchStart;
      chooseColorPanel(slot);
      drawColorComponents(colorIndex, components);
    }

    colorBatchStart += 9;
  }

  lines.push('');
  lines.push('# ==========================================');
  lines.push('# 全图绘制完成，复位光标至 (0,0)');
  lines.push('# ==========================================');

  moveTo(0, 0);

  return lines.join('\n');
};

export type MacroAlgorithmType = "segment" | "dfs";
export interface MacroAlgorithm {
  type: MacroAlgorithmType,
  generator: MacroGenerator,
};
export const MacroAlgorithmMap: Record<MacroAlgorithmType, MacroAlgorithm> = {
  "dfs": { type: "dfs", generator: generateZigMacroScriptDFS },
  "segment": { type: "segment", generator: generateZigMacroScriptBySegment },
};