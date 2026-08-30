import { rgbToTomodachiHSV, type RGBColor } from "./color";

export const generateZigMacroScriptBySegment = (
  w: number,
  h: number,
  palette: RGBColor[],
  pIndices: (number | null)[][],
  delay: number
): string => {
  type Point = {
    x: number;
    y: number;
  };

  type Segment = {
    a: Point;
    b: Point;
    length: number;
  };

  type ComponentPlan = {
    segments: Segment[];
  };

  const lines: string[] = [];

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

  let curColorPanelIdx = 0;

  // ------------------------------------------------------------
  // 基础宏
  // ------------------------------------------------------------

  const tap = (button: string, space: number = 0) => lines.push(`${' '.repeat(space)}TAP ${delay}ms ${delay}ms ${button}`);

  const tapMultiple = (button: string, count: number) => {
    if (count <= 0) return;

    if (count === 1) {
      tap(button);
      return;
    }

    lines.push(`REPEAT ${count}`);
    tap(button, 2);
    lines.push('END');
  };

  const wait = (ms: number) => lines.push(`WAIT ${ms}ms`);

  const down = (button: string) => {
    lines.push(`DOWN ${button}`);
    wait(delay);
  };

  const up = (button: string) => {
    lines.push(`UP ${button}`);
    wait(delay);
  };

  // ------------------------------------------------------------
  // 调色板
  // ------------------------------------------------------------

  const initColorPanel = () => {
    lines.push('# --- 初始化调色板面板 ---');

    tap('Y');

    tapMultiple('DPAD_DOWN', 10);
    tapMultiple('DPAD_UP', 8);

    tap('Y');

    tap('R');
    tap('R');
    tap('R');

    wait(100);

    tap('A');

    curColorPanelIdx = 0;
  };

  const chooseColorPanel = (idx: number) => {
    if (curColorPanelIdx === idx) {
      return;
    }

    tap('Y');

    if (idx > curColorPanelIdx) {
      tapMultiple('DPAD_DOWN', idx - curColorPanelIdx);
    } else {
      tapMultiple('DPAD_UP', curColorPanelIdx - idx);
    }

    curColorPanelIdx = idx;

    tap('A');
  };

  const resetHSVColorPanel = () => {
    lines.push('# --- 复位 HSV 调色板 ---');

    wait(100);

    lines.push('STICK LEFT_STICK -100 +100');
    wait(100);

    lines.push('DOWN ZL');
    wait(5000);

    lines.push('UP ZL');
    wait(100);

    lines.push('RESET_STICK LEFT_STICK');
    wait(100);
  };

  const chooseHSVColor = (
    slotIdx: number,
    colorIdx: number
  ) => {
    const color = palette[colorIdx - 1];

    if (!color) {
      return;
    }

    const hsv = rgbToTomodachiHSV(
      color.r,
      color.g,
      color.b
    );

    lines.push(
      `\n# 配置色槽 Slot ${slotIdx} <- 调色板颜色 ${colorIdx}: ` +
      `RGB(${color.r},${color.g},${color.b})`
    );

    wait(100);

    chooseColorPanel(slotIdx);

    wait(100);

    tap('Y');
    wait(100);

    tap('Y');
    wait(100);

    resetHSVColorPanel();

    wait(100);

    tapMultiple('ZR', hsv.hTicks);

    wait(100);

    tapMultiple('DPAD_RIGHT', hsv.sTicks);

    wait(100);

    tapMultiple('DPAD_DOWN', hsv.vTicks);

    wait(100);

    tap('A');

    wait(100);
  };

  // ------------------------------------------------------------
  // 光标移动
  // ------------------------------------------------------------

  let curX = 0;
  let curY = 0;

  const moveTo = (
    targetX: number,
    targetY: number
  ) => {
    const dx = targetX - curX;
    const dy = targetY - curY;

    if (dx > 0) {
      tapMultiple('DPAD_RIGHT', dx);
    } else if (dx < 0) {
      tapMultiple('DPAD_LEFT', -dx);
    }

    if (dy > 0) {
      tapMultiple('DPAD_DOWN', dy);
    } else if (dy < 0) {
      tapMultiple('DPAD_UP', -dy);
    }

    curX = targetX;
    curY = targetY;
  };

  const cellId = (x: number, y: number) => {
    return y * w + x;
  };

  const manhattan = (
    a: Point,
    b: Point
  ) => {
    return Math.abs(a.x - b.x) +
      Math.abs(a.y - b.y);
  };

  const directionFromTo = (
    from: Point,
    to: Point
  ): string => {
    const dx = to.x - from.x;
    const dy = to.y - from.y;

    if (dx === 1 && dy === 0) return 'DPAD_RIGHT';
    if (dx === -1 && dy === 0) return 'DPAD_LEFT';
    if (dx === 0 && dy === 1) return 'DPAD_DOWN';
    if (dx === 0 && dy === -1) return 'DPAD_UP';

    throw new Error(
      `Invalid adjacent move: (${from.x},${from.y}) -> (${to.x},${to.y})`
    );
  };

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
      curX = end.x;
      curY = end.y;
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

    curX = end.x;
    curY = end.y;
  };

  // ------------------------------------------------------------
  // A 已经按住：
  // 移动 1 格进入相邻线段
  // ------------------------------------------------------------

  const moveHeldOneStep = (
    target: Point
  ) => {
    const current: Point = {
      x: curX,
      y: curY,
    };

    if (
      manhattan(current, target) !== 1
    ) {
      throw new Error(
        `moveHeldOneStep requires adjacent point: ` +
        `(${curX},${curY}) -> (${target.x},${target.y})`
      );
    }

    const direction = directionFromTo(
      current,
      target
    );

    tap(direction);

    curX = target.x;
    curY = target.y;
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
        const nx = curX + dx;
        const ny = curY + dy;

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
            { x: curX, y: curY },
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
            curX,
            curY,
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
          curX,
          curY,
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
            { x: curX, y: curY },
            seg.a
          ),
          manhattan(
            { x: curX, y: curY },
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
              { x: curX, y: curY },
              seg.a
            ),
            manhattan(
              { x: curX, y: curY },
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