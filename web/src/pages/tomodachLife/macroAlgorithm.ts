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

type Tool = 'pen' | 'fill' | 'earse';
const ToolIndex: Record<Tool, number> = {
  'fill': 5,
  'pen': 6,
  'earse': 7,
};

type Direction = 'DPAD_LEFT' | 'DPAD_RIGHT' | 'DPAD_UP' | 'DPAD_DOWN';
const directions = [
  { dx: 1, dy: 0, button: 'DPAD_RIGHT' },
  { dx: 0, dy: 1, button: 'DPAD_DOWN' },
  { dx: -1, dy: 0, button: 'DPAD_LEFT' },
  { dx: 0, dy: -1, button: 'DPAD_UP' },
] as const;

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
  curTool: Tool,

  tap(button: string, space?: number): void;
  tapMultiple(button: string, count: number): void;
  wait(ms: number): void;
  down(button: string): void;
  up(button: string): void;

  /**
   * 注释
   */
  comment(msg: string): void;
  /**
   * 多行注释
   */
  comments(msgs: string[]): void;

  /**
   * 初始化工具槽位
   */
  initToolPanel(): void;
  /**
   * 选择工具槽位
   */
  chooseTool(tool: Tool): void;
  /**
   * 油漆桶, 将当前所在坐标的像素相邻连通的相同同色(无色)像素填入当前选择的颜色.
   * 使用后当前工具将会切换成 'fill'
   */
  fill(): void;
  /**
   * 清除当前坐标的像素颜色, 使用后当前工具将会切换成 'earse'
   */
  earse(): void;
  /**
   * 开始连续清除, 使用后当前工具会切换成 'earse'
   * 需要与 `endEarse()` 一同使用.
   */
  beginEarse(): void;
  /**
   * 停止连续清除, 使用后当前工具会切换成 'earse'.
   * 需要与 `beginEarse()` 一同使用.
   */
  endEarse(): void;
  /**
   * 将选择颜色填入当前坐标, 使用后当前工具会切换成 'pen'
   */
  draw(): void;
  /**
   * 开始连续绘制, 使用后当前工具会切换成 'pen'
   * 需要与 `endDraw()` 一同使用.
   */
  beginDraw(): void;
  /**
   * 停止连续绘制, 使用后当前工具会切换成 'pen'.
   * 需要与 `beginDraw()` 一同使用.
   */
  endDraw(): void;

  /**
   * 初始化颜色面板
   */
  initColorPanel(): void;
  /**
   * 选择指定颜色面板下标的颜色
   * @param idx 颜色面板下标
   */
  chooseColorPanel(idx: number): void;
  /**
   * 重置HSV颜色选色盘到左上角和(色域)最左边
   */
  resetHSVColorPanel(): void;
  /**
   * 自动选择HSV颜色
   * @param slotIdx 面板颜色下标
   * @param colorIdx 离散颜色下标
   */
  chooseHSVColor(slotIdx: number, colorIdx: number): void;

  goto(direction: Direction, times: number): void,
  moveTo(targetX: number, targetY: number): void;
  getId(x: number, y: number): number;
  manhattanDistance(a: Point, b: Point): number;
  directionFromTo(from: Point, to: Point): Direction;
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
    curTool: 'pen',

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

    comment: (msg) => {
      const msgs = msg.split("\n");
      msgs.forEach(line => {
        if (line.trim()) {
          context.lines.push(`# ${line}`);
        } else {
          context.lines.push(``);
        }
      });
    },
    comments: (msgs) => msgs.forEach(line => context.comment(line)),

    initToolPanel: () => {
      context.comment('--- 初始化工具面板 ---');

      // reset pen size
      context.chooseTool('pen');
      context.tapMultiple('X', 2);
      context.tapMultiple('DPAD_LEFT', 2);
      context.tapMultiple('A', 2);

      // reset earse size
      context.chooseTool('earse');
      context.tap('X');
      context.tapMultiple('DPAD_LEFT', 2);
      context.tapMultiple('A', 2);

      // reset to pen
      context.chooseTool('pen');
    },
    chooseTool: (tool) => {
      const curTool = context.curTool;
      const curToolIdx = ToolIndex[curTool];
      const nextToolIdx = ToolIndex[tool];
      if (curToolIdx === nextToolIdx) return;

      context.tap('X');
      const direction = curToolIdx > nextToolIdx ? 'DPAD_LEFT' : 'DPAD_RIGHT';
      context.tapMultiple(direction, Math.abs(curToolIdx - nextToolIdx));
      context.tap('A');
      context.curTool = tool;
    },
    fill: () => {
      context.chooseTool('fill');
      context.tap('A');
    },
    earse: () => {
      context.chooseTool('earse');
      context.tap('A');
    },
    beginEarse: () => {
      context.chooseTool('earse');
      context.down("A");
    },
    endEarse: () => context.up("A"),
    draw: () => {
      context.chooseTool('pen');
      context.tap("A");
    },
    beginDraw: () => {
      context.chooseTool('pen');
      context.down("A");
    },
    endDraw: () => context.up("A"),

    initColorPanel: () => {
      context.comment('--- 初始化调色板面板 ---');

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
      context.comment('--- 复位 HSV 调色板 ---');

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

      context.comments([
        "",
        `配置色槽 Slot ${slotIdx} <- ` +
        `调色板颜色 ${colorIdx}: ` +
        `RGB(${color.r},${color.g},${color.b})`
      ]);

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

    goto: (direction, times) => context.tapMultiple(direction, times),
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

      for (const d of directions) {
        if (d.dx === dx && d.dy === dy) {
          return d.button;
        }
      }

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

  type ChainItem = {
    segmentIndex: number;
    start: Point;
    end: Point;
  };

  type SegmentChain = {
    items: ChainItem[];
    start: Point;
    end: Point;
  };

  type SegmentPlan = {
    segments: Segment[];
    chains: SegmentChain[];
    pixelCount: number;
    connectionCount: number;
  };

  type ComponentPlan = {
    horizontal: SegmentPlan;
    vertical: SegmentPlan;
  };

  type ConnectionEdge = {
    p: number;
    q: number;
    u: number;
    v: number;
  };

  const context = createZigMacroScriptContext(w, h, palette, pIndices, delay);

  const {
    goto,
    beginDraw,
    endDraw,
    initToolPanel,
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
  const totalCells = w * h;

  // context.comment('==========================================');
  // context.comment('Tomodachi Life 自动化绘制宏脚本');
  // context.comment('线段优化策略:');
  // context.comment('1. 同色像素按水平/垂直最大连续线段压缩');
  // context.comment('2. 预先建立“线段连接图”，全局规划可连续保持 A 的线段链');
  // context.comment('3. 优先保留受限端点连接，并避免闭环导致的无效回路');
  // context.comment('4. 每个连通块同时评估 H/V 两种方案，按实际移动 + A 开关时间择优');
  // context.comment('5. A 按住时只经过当前颜色像素，保证不串色、不漏像素');
  // context.comment(`尺寸: ${w}x${h} | 颜色数: ${palette.length} | 延迟: ${delay}ms`);
  // context.comment('==========================================\n');
  context.comments([
    '==========================================',
    'Tomodachi Life 自动化绘制宏脚本',
    '线段优化策略',
    `尺寸: ${w}x${h} | 颜色数: ${palette.length} | 延迟: ${delay}ms`,
    '==========================================',
    ''
  ]);

  // ------------------------------------------------------------
  // 组件标记：避免每个线段都创建 Set，且 H/V 复用同一块连续内存。
  // ------------------------------------------------------------

  const componentMark = new Int32Array(totalCells);
  let componentMarkStamp = 0;

  const buildSegments = (
    pointIds: number[],
    orientation: 'H' | 'V'
  ): Segment[] => {
    componentMarkStamp++;
    const stamp = componentMarkStamp;

    for (const id of pointIds) {
      componentMark[id] = stamp;
    }

    const segments: Segment[] = [];

    if (orientation === 'H') {
      for (const id of pointIds) {
        const x = id % w;
        const y = Math.floor(id / w);

        if (x > 0 && componentMark[id - 1] === stamp) {
          continue;
        }

        let endX = x;
        let nextId = id + 1;
        while (
          endX + 1 < w &&
          componentMark[nextId] === stamp
        ) {
          endX++;
          nextId++;
        }

        segments.push({
          a: { x, y },
          b: { x: endX, y },
          length: endX - x + 1,
        });
      }
    } else {
      for (const id of pointIds) {
        const x = id % w;
        const y = Math.floor(id / w);

        if (y > 0 && componentMark[id - w] === stamp) {
          continue;
        }

        let endY = y;
        let nextId = id + w;
        while (
          endY + 1 < h &&
          componentMark[nextId] === stamp
        ) {
          endY++;
          nextId += w;
        }

        segments.push({
          a: { x, y },
          b: { x, y: endY },
          length: endY - y + 1,
        });
      }
    }

    return segments;
  };

  // ------------------------------------------------------------
  // 并查集：用于“已经形成的线段链”之间的后续安全连接。
  // ------------------------------------------------------------

  const createDsu = (n: number) => {
    const parent = new Int32Array(n);
    const rank = new Uint8Array(n);

    for (let i = 0; i < n; i++) {
      parent[i] = i;
    }

    const find = (x: number): number => {
      let root = x;
      while (parent[root] !== root) {
        root = parent[root];
      }
      while (parent[x] !== x) {
        const next = parent[x];
        parent[x] = root;
        x = next;
      }
      return root;
    };

    const union = (a: number, b: number): boolean => {
      let ra = find(a);
      let rb = find(b);
      if (ra === rb) return false;

      if (rank[ra] < rank[rb]) {
        [ra, rb] = [rb, ra];
      }

      parent[rb] = ra;
      if (rank[ra] === rank[rb]) {
        rank[ra]++;
      }
      return true;
    };

    return { find, union };
  };

  // ------------------------------------------------------------
  // 在线段端点图上建立“最大化连续连接”的线性森林。
  //
  // 每个端点最多使用一次，因此一个线段最多只有前/后两个连接。
  // 先用多种简单贪心次序尝试匹配，再拆掉闭环，最后做一次安全补边。
  // 这样比“边画边看最近端点”更不容易把后面的线段接成死路。
  // ------------------------------------------------------------

  const buildLinearForest = (segments: Segment[]): SegmentChain[] => {
    const segmentCount = segments.length;

    if (segmentCount === 0) {
      return [];
    }

    if (segmentCount === 1) {
      const seg = segments[0];
      return [
        {
          items: [
            {
              segmentIndex: 0,
              start: seg.a,
              end: seg.b,
            },
          ],
          start: seg.a,
          end: seg.b,
        },
      ];
    }

    // 一个单像素线段的 a/b 是同一点，因此这里保存“多个逻辑端口”，
    // 不能用 Map<number, number> 简单覆盖，否则会丢掉第二个连接机会。
    const endpointToPorts = new Map<number, number[]>();

    const registerEndpoint = (id: number, port: number) => {
      const ports = endpointToPorts.get(id);
      if (ports) {
        ports.push(port);
      } else {
        endpointToPorts.set(id, [port]);
      }
    };

    for (let i = 0; i < segmentCount; i++) {
      const seg = segments[i];
      registerEndpoint(cellId(seg.a.x, seg.a.y), i * 2);
      registerEndpoint(cellId(seg.b.x, seg.b.y), i * 2 + 1);
    }

    const edges: ConnectionEdge[] = [];

    for (let i = 0; i < segmentCount; i++) {
      const seg = segments[i];
      const endpoints = [seg.a, seg.b];

      for (let localPort = 0; localPort < 2; localPort++) {
        const point = endpoints[localPort];
        const port = i * 2 + localPort;

        const neighbors = [
          [point.x + 1, point.y],
          [point.x - 1, point.y],
          [point.x, point.y + 1],
          [point.x, point.y - 1],
        ] as const;

        for (const [nx, ny] of neighbors) {
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) {
            continue;
          }

          const otherPorts = endpointToPorts.get(cellId(nx, ny));
          if (!otherPorts) {
            continue;
          }

          for (const otherPort of otherPorts) {
            if (otherPort === port) {
              continue;
            }

            const otherSegment = Math.floor(otherPort / 2);
            if (otherSegment === i || port > otherPort) {
              continue;
            }

            edges.push({
              p: port,
              q: otherPort,
              u: i,
              v: otherSegment,
            });
          }
        }
      }
    }

    if (edges.length === 0) {
      return segments.map((seg, index) => ({
        items: [
          {
            segmentIndex: index,
            start: seg.a,
            end: seg.b,
          },
        ],
        start: seg.a,
        end: seg.b,
      }));
    }

    const portDegree = new Int8Array(segmentCount * 2);
    const segmentDegree = new Int8Array(segmentCount);

    for (const edge of edges) {
      portDegree[edge.p]++;
      portDegree[edge.q]++;
      segmentDegree[edge.u]++;
      segmentDegree[edge.v]++;
    }

    const baseOrder = edges.map((_, index) => index);
    let bestConnectionCount = -1;
    let bestConnections: Int32Array | null = null;

    // 多个排序策略只影响“同样都是可连接”的边怎么抢占端点。
    // 不增加宏运行成本，却能显著降低局部贪心造成的坏链。
    const comparators = [
      (a: ConnectionEdge, b: ConnectionEdge) =>
        portDegree[a.p] + portDegree[a.q] - (portDegree[b.p] + portDegree[b.q]) ||
        segmentDegree[a.u] + segmentDegree[a.v] -
        (segmentDegree[b.u] + segmentDegree[b.v]),

      (a: ConnectionEdge, b: ConnectionEdge) =>
        segmentDegree[a.u] + segmentDegree[a.v] -
        (segmentDegree[b.u] + segmentDegree[b.v]) ||
        portDegree[a.p] + portDegree[a.q] - (portDegree[b.p] + portDegree[b.q]),

      (a: ConnectionEdge, b: ConnectionEdge) =>
        Math.max(portDegree[a.p], portDegree[a.q]) -
        Math.max(portDegree[b.p], portDegree[b.q]) ||
        Math.min(portDegree[a.p], portDegree[a.q]) -
        Math.min(portDegree[b.p], portDegree[b.q]),
    ];

    for (const compare of comparators) {
      const orderedIndices = baseOrder.slice();
      orderedIndices.sort((ia, ib) => {
        const result = compare(edges[ia], edges[ib]);
        return result || ia - ib;
      });

      const conn = new Int32Array(segmentCount * 2);
      conn.fill(-1);
      const usedPort = new Uint8Array(segmentCount * 2);

      // 第一阶段：端点不重复的最大化贪心匹配。
      for (const edgeIndex of orderedIndices) {
        const edge = edges[edgeIndex];

        if (usedPort[edge.p] || usedPort[edge.q]) {
          continue;
        }

        usedPort[edge.p] = 1;
        usedPort[edge.q] = 1;
        conn[edge.p] = edge.q;
        conn[edge.q] = edge.p;
      }

      // 第二阶段：选中的连接可能形成环。
      // 一个环无法作为“开放式 A-held 路径”一次全部走完，所以每个环拆掉一条边。
      const degree = new Uint8Array(segmentCount);
      for (let i = 0; i < segmentCount; i++) {
        degree[i] =
          (conn[i * 2] >= 0 ? 1 : 0) +
          (conn[i * 2 + 1] >= 0 ? 1 : 0);
      }

      const visited = new Uint8Array(segmentCount);

      // 先标记所有路径形态。
      for (let start = 0; start < segmentCount; start++) {
        if (visited[start] || degree[start] !== 1) {
          continue;
        }

        let current = start;
        let previous = -1;

        while (current >= 0 && !visited[current]) {
          visited[current] = 1;

          const p0 = current * 2;
          const nextPort =
            conn[p0] >= 0 && Math.floor(conn[p0] / 2) !== previous
              ? p0
              : p0 + 1;

          if (conn[nextPort] < 0) {
            break;
          }

          const next = Math.floor(conn[nextPort] / 2);
          previous = current;
          current = next;
        }
      }

      // 剩余未访问节点全部属于闭环。
      for (let start = 0; start < segmentCount; start++) {
        if (visited[start] || degree[start] !== 2) {
          continue;
        }

        const breakPort = start * 2;
        const otherPort = conn[breakPort];

        if (otherPort >= 0) {
          conn[breakPort] = -1;
          conn[otherPort] = -1;
          usedPort[breakPort] = 0;
          usedPort[otherPort] = 0;
        }

        let current = start;
        let previous = -1;
        while (current >= 0 && !visited[current]) {
          visited[current] = 1;

          const p0 = current * 2;
          const candidate0 = conn[p0];
          const candidate1 = conn[p0 + 1];

          let next = -1;
          if (candidate0 >= 0) {
            const c0 = Math.floor(candidate0 / 2);
            if (c0 !== previous) next = c0;
          }
          if (next < 0 && candidate1 >= 0) {
            const c1 = Math.floor(candidate1 / 2);
            if (c1 !== previous) next = c1;
          }

          previous = current;
          current = next;
        }
      }

      // 第三阶段：拆环后，用剩余自由端点把不同链安全地继续拼起来。
      const dsu = createDsu(segmentCount);

      for (let i = 0; i < segmentCount; i++) {
        for (let port = 0; port < 2; port++) {
          const otherPort = conn[i * 2 + port];
          if (otherPort < 0) continue;
          const j = Math.floor(otherPort / 2);
          if (i < j) {
            dsu.union(i, j);
          }
        }
      }

      usedPort.fill(0);
      for (let port = 0; port < conn.length; port++) {
        if (conn[port] >= 0) usedPort[port] = 1;
      }

      for (const edgeIndex of orderedIndices) {
        const edge = edges[edgeIndex];

        if (usedPort[edge.p] || usedPort[edge.q]) {
          continue;
        }

        if (dsu.find(edge.u) === dsu.find(edge.v)) {
          continue;
        }

        conn[edge.p] = edge.q;
        conn[edge.q] = edge.p;
        usedPort[edge.p] = 1;
        usedPort[edge.q] = 1;
        dsu.union(edge.u, edge.v);
      }

      let connectionCount = 0;
      for (let port = 0; port < conn.length; port++) {
        if (conn[port] >= 0) connectionCount++;
      }
      connectionCount = Math.floor(connectionCount / 2);

      if (connectionCount > bestConnectionCount) {
        bestConnectionCount = connectionCount;
        bestConnections = conn;
      }
    }

    if (!bestConnections) {
      throw new Error('Failed to build segment connection plan');
    }

    // ----------------------------------------------------------
    // 把“线段连接图”展开成若干条可以一次 A-held 走完的链。
    // ----------------------------------------------------------

    const degree = new Uint8Array(segmentCount);
    for (let i = 0; i < segmentCount; i++) {
      degree[i] =
        (bestConnections[i * 2] >= 0 ? 1 : 0) +
        (bestConnections[i * 2 + 1] >= 0 ? 1 : 0);
    }

    const chains: SegmentChain[] = [];
    const visited = new Uint8Array(segmentCount);

    const getPortPoint = (segmentIndex: number, port: number): Point => {
      const seg = segments[segmentIndex];
      return port === 0 ? seg.a : seg.b;
    };

    const appendChain = (startSegment: number) => {
      const items: ChainItem[] = [];
      let currentSegment = startSegment;
      let entryPort = 0;
      if (degree[currentSegment] === 1) {
        // 从“未连接”的端点进入，画完线段后正好从已连接端点出去。
        const connectedPort =
          bestConnections[currentSegment * 2] >= 0 ? 0 : 1;
        entryPort = connectedPort === 0 ? 1 : 0;
      }

      while (currentSegment >= 0 && !visited[currentSegment]) {
        visited[currentSegment] = 1;

        const exitPort = entryPort === 0 ? 1 : 0;
        // const seg = segments[currentSegment];

        items.push({
          segmentIndex: currentSegment,
          start: getPortPoint(currentSegment, entryPort),
          end: getPortPoint(currentSegment, exitPort),
        });

        const nextPort = bestConnections[currentSegment * 2 + exitPort];
        if (nextPort < 0) {
          break;
        }

        const nextSegment = Math.floor(nextPort / 2);
        entryPort = nextPort % 2;
        currentSegment = nextSegment;
      }

      const first = items[0];
      const last = items[items.length - 1];

      chains.push({
        items,
        start: first.start,
        end: last.end,
      });
    };

    // 先处理所有真正的“路径端点”。
    for (let i = 0; i < segmentCount; i++) {
      if (!visited[i] && degree[i] <= 1) {
        appendChain(i);
      }
    }

    // 理论上这里只可能剩下孤立点；这里保底，避免任何极端情况下漏画。
    for (let i = 0; i < segmentCount; i++) {
      if (!visited[i]) {
        appendChain(i);
      }
    }

    return chains;
  };

  const buildSegmentPlan = (
    pointCount: number,
    segments: Segment[]
  ): SegmentPlan => {
    const chains = buildLinearForest(segments);

    let connectionCount = 0;
    for (const chain of chains) {
      connectionCount += Math.max(0, chain.items.length - 1);
    }

    return {
      segments,
      chains,
      pixelCount: pointCount,
      connectionCount,
    };
  };

  // ------------------------------------------------------------
  // 一次扫描整张图，直接建立所有颜色的 4 邻接连通块。
  // 相比“每个颜色重新扫描 w*h”，组件建立阶段明显更快。
  // ------------------------------------------------------------

  const buildAllColorComponents = (): Map<number, ComponentPlan[]> => {
    const componentsByColor = new Map<number, ComponentPlan[]>();
    const visited = new Uint8Array(totalCells);
    const queue: number[] = [];

    for (let y = 0; y < h; y++) {
      const row = pIndices[y];
      for (let x = 0; x < w; x++) {
        const pixelIndex = row?.[x];

        if (pixelIndex === undefined || pixelIndex === null) {
          continue;
        }

        const startId = cellId(x, y);
        if (visited[startId]) {
          continue;
        }

        const pointIds: number[] = [];
        queue.length = 0;
        queue.push(startId);
        visited[startId] = 1;

        for (let qi = 0; qi < queue.length; qi++) {
          const id = queue[qi];
          pointIds.push(id);

          const cx = id % w;
          const cy = Math.floor(id / w);
          const left = cx > 0 ? id - 1 : -1;
          const right = cx + 1 < w ? id + 1 : -1;
          const upId = cy > 0 ? id - w : -1;
          const downId = cy + 1 < h ? id + w : -1;

          if (left >= 0 && !visited[left]) {
            const nx = cx - 1;
            if (pIndices[cy]?.[nx] === pixelIndex) {
              visited[left] = 1;
              queue.push(left);
            }
          }

          if (right >= 0 && !visited[right]) {
            const nx = cx + 1;
            if (pIndices[cy]?.[nx] === pixelIndex) {
              visited[right] = 1;
              queue.push(right);
            }
          }

          if (upId >= 0 && !visited[upId]) {
            if (pIndices[cy - 1]?.[cx] === pixelIndex) {
              visited[upId] = 1;
              queue.push(upId);
            }
          }

          if (downId >= 0 && !visited[downId]) {
            if (pIndices[cy + 1]?.[cx] === pixelIndex) {
              visited[downId] = 1;
              queue.push(downId);
            }
          }
        }

        const horizontalSegments = buildSegments(pointIds, 'H');
        const verticalSegments = buildSegments(pointIds, 'V');

        const component: ComponentPlan = {
          horizontal: buildSegmentPlan(pointIds.length, horizontalSegments),
          vertical: buildSegmentPlan(pointIds.length, verticalSegments),
        };

        const colorIndex = pixelIndex + 1;
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

  // ------------------------------------------------------------
  // 点到线段的 Manhattan 距离：比只看端点更准确。
  // 用于颜色 / 连通块的下一目标选择。
  // ------------------------------------------------------------

  const distanceToSegment = (point: Point, seg: Segment): number => {
    let dx = 0;
    let dy = 0;

    if (seg.a.y === seg.b.y) {
      if (point.x < Math.min(seg.a.x, seg.b.x)) {
        dx = Math.min(seg.a.x, seg.b.x) - point.x;
      } else if (point.x > Math.max(seg.a.x, seg.b.x)) {
        dx = point.x - Math.max(seg.a.x, seg.b.x);
      }
      dy = Math.abs(point.y - seg.a.y);
    } else {
      if (point.y < Math.min(seg.a.y, seg.b.y)) {
        dy = Math.min(seg.a.y, seg.b.y) - point.y;
      } else if (point.y > Math.max(seg.a.y, seg.b.y)) {
        dy = point.y - Math.max(seg.a.y, seg.b.y);
      }
      dx = Math.abs(point.x - seg.a.x);
    }

    return dx + dy;
  };

  const distanceToComponent = (
    component: ComponentPlan,
    x: number,
    y: number
  ): number => {
    const point = { x, y };
    let best = Infinity;

    // H 线段已经完整覆盖所有像素，因此距离是精确的。
    for (const seg of component.horizontal.segments) {
      const distance = distanceToSegment(point, seg);
      if (distance < best) best = distance;
    }

    return best;
  };

  // ------------------------------------------------------------
  // 根据当前光标，把一组线段链排序。
  // 同时决定每条链是正向还是反向，避免为了“最近入口”重新生成链对象。
  // ------------------------------------------------------------

  type OrderedChain = {
    chainIndex: number;
    reverse: boolean;
  };

  const orderChains = (
    plan: SegmentPlan,
    x: number,
    y: number
  ): {
    order: OrderedChain[];
    moveCount: number;
    score: number;
  } => {
    const chains = plan.chains;
    const remaining = new Uint8Array(chains.length);
    remaining.fill(1);

    const order: OrderedChain[] = [];
    let current: Point = { x, y };
    let moveCount = 0;

    // 每条链内部固定：
    //   线段内部移动 = sum(length - 1)
    //   链间相邻连接 = items.length - 1
    const fixedInsideMoves =
      plan.pixelCount - plan.segments.length + plan.connectionCount;

    moveCount += fixedInsideMoves;

    while (order.length < chains.length) {
      let bestIndex = -1;
      let bestReverse = false;
      let bestDistance = Infinity;
      let bestLength = -1;

      for (let i = 0; i < chains.length; i++) {
        if (!remaining[i]) continue;

        const chain = chains[i];
        const distStart = manhattan(current, chain.start);
        const distEnd = manhattan(current, chain.end);

        let distance = distStart;
        let reverse = false;

        if (distEnd < distStart) {
          distance = distEnd;
          reverse = true;
        }

        const chainLength = chain.items.length;

        if (
          distance < bestDistance ||
          (distance === bestDistance && chainLength > bestLength)
        ) {
          bestIndex = i;
          bestReverse = reverse;
          bestDistance = distance;
          bestLength = chainLength;
        }
      }

      if (bestIndex < 0) {
        break;
      }

      remaining[bestIndex] = 0;
      order.push({
        chainIndex: bestIndex,
        reverse: bestReverse,
      });

      moveCount += bestDistance;

      const selected = chains[bestIndex];
      current = bestReverse ? selected.start : selected.end;
    }

    // 每条 stroke 会产生一次 DOWN A + 一次 UP A，二者各自包含一个 WAIT delay。
    // TAP / REPEAT 的移动则包含两个 delay。
    // 因此用“2*移动步数 + 2*stroke 数”直接比较预计宏执行时间。
    const score = moveCount * 2 + chains.length * 2;

    return {
      order,
      moveCount,
      score,
    };
  };

  const drawSegmentPlan = (plan: SegmentPlan) => {
    const ordered = orderChains(plan, context.curX, context.curY);

    for (const item of ordered.order) {
      const chain = plan.chains[item.chainIndex];
      const itemCount = chain.items.length;

      const first = item.reverse
        ? chain.items[itemCount - 1]
        : chain.items[0];
      const strokeStart = item.reverse ? first.end : first.start;

      moveTo(strokeStart.x, strokeStart.y);
      beginDraw();

      for (let j = 0; j < itemCount; j++) {
        const chainItem = item.reverse
          ? chain.items[itemCount - 1 - j]
          : chain.items[j];

        const start = item.reverse ? chainItem.end : chainItem.start;

        if (j > 0) {
          const previousItem = item.reverse
            ? chain.items[itemCount - j]
            : chain.items[j - 1];

          const previousEnd = item.reverse
            ? previousItem.start
            : previousItem.end;

          if (
            manhattan(previousEnd, start) !== 1
          ) {
            endDraw();
            throw new Error(
              `Invalid segment chain connection: ` +
              `(${previousEnd.x},${previousEnd.y}) -> ` +
              `(${start.x},${start.y})`
            );
          }

          const direction = directionFromTo(previousEnd, start);
          goto(direction, 1);
          context.curX = start.x;
          context.curY = start.y;
        }

        const end = item.reverse ? chainItem.start : chainItem.end;

        const dx = end.x - start.x;
        const dy = end.y - start.y;

        if (dx === 0 && dy === 0) {
          // 单点线段，无需移动。
        } else if (dy === 0) {
          goto(dx > 0 ? 'DPAD_RIGHT' : 'DPAD_LEFT', Math.abs(dx));
        } else if (dx === 0) {
          goto(dy > 0 ? 'DPAD_DOWN' : 'DPAD_UP', Math.abs(dy));
        } else {
          endDraw();
          throw new Error(
            `Invalid segment direction: ` +
            `(${start.x},${start.y}) -> (${end.x},${end.y})`
          );
        }

        context.curX = end.x;
        context.curY = end.y;
      }

      endDraw();
    }
  };

  // ------------------------------------------------------------
  // 兼容性候选：保留“边走边找相邻线段”的原始线段思想。
  // 与新版全局线段链方案竞争，最终按实际预计执行时间择优。
  // 同时修复原实现中“首条线段也可能走进 adjacent 分支、却尚未 DOWN A”
  // 的隐患：第一条 stroke 始终先 moveTo + DOWN A。
  // ------------------------------------------------------------

  const buildGreedySegmentPlan = (
    segments: Segment[],
    x: number,
    y: number
  ): SegmentPlan => {
    const used = new Uint8Array(segments.length);
    let remaining = segments.length;
    const chains: SegmentChain[] = [];

    const findNearest = (current: Point): { index: number; start: Point } => {
      let bestIndex = -1;
      let bestStart: Point | null = null;
      let bestDistance = Infinity;
      let bestLength = -1;

      for (let i = 0; i < segments.length; i++) {
        if (used[i]) continue;

        const seg = segments[i];
        const distA = manhattan(current, seg.a);
        const distB = manhattan(current, seg.b);

        let start = seg.a;
        let distance = distA;
        if (distB < distA) {
          start = seg.b;
          distance = distB;
        }

        if (
          distance < bestDistance ||
          (distance === bestDistance && seg.length > bestLength)
        ) {
          bestDistance = distance;
          bestIndex = i;
          bestStart = start;
          bestLength = seg.length;
        }
      }

      if (bestIndex < 0 || !bestStart) {
        throw new Error('No available segment in greedy planner');
      }

      return { index: bestIndex, start: bestStart };
    };

    const findAdjacent = (current: Point): { index: number; start: Point } | null => {
      let bestIndex = -1;
      let bestStart: Point | null = null;
      let bestLength = -1;

      for (let i = 0; i < segments.length; i++) {
        if (used[i]) continue;

        const seg = segments[i];

        if (manhattan(current, seg.a) === 1) {
          if (seg.length > bestLength) {
            bestIndex = i;
            bestStart = seg.a;
            bestLength = seg.length;
          }
        }

        if (manhattan(current, seg.b) === 1) {
          if (seg.length > bestLength) {
            bestIndex = i;
            bestStart = seg.b;
            bestLength = seg.length;
          }
        }
      }

      return bestIndex < 0 || !bestStart
        ? null
        : { index: bestIndex, start: bestStart };
    };

    let current: Point = { x, y };

    while (remaining > 0) {
      const first = findNearest(current);
      const items: ChainItem[] = [];

      let segmentIndex = first.index;
      let start = first.start;

      while (true) {
        const seg = segments[segmentIndex];
        const startIsA = start.x === seg.a.x && start.y === seg.a.y;
        const end = startIsA ? seg.b : seg.a;

        items.push({
          segmentIndex,
          start,
          end,
        });

        used[segmentIndex] = 1;
        remaining--;
        current = end;

        const next = findAdjacent(current);
        if (!next) break;

        segmentIndex = next.index;
        start = next.start;
      }

      chains.push({
        items,
        start: items[0].start,
        end: items[items.length - 1].end,
      });
    }

    let connectionCount = 0;
    for (const chain of chains) {
      connectionCount += Math.max(0, chain.items.length - 1);
    }

    return {
      segments,
      chains,
      pixelCount: segments.reduce((sum, seg) => sum + seg.length, 0),
      connectionCount,
    };
  };

  const chooseBestOrientation = (
    component: ComponentPlan
  ): SegmentPlan => {
    const candidates: SegmentPlan[] = [];

    for (const basePlan of [component.horizontal, component.vertical]) {
      candidates.push(basePlan);
      candidates.push(
        buildGreedySegmentPlan(
          basePlan.segments,
          context.curX,
          context.curY
        )
      );
    }

    let bestPlan = candidates[0];
    let bestScore = orderChains(
      bestPlan,
      context.curX,
      context.curY
    ).score;

    for (let i = 1; i < candidates.length; i++) {
      const plan = candidates[i];
      const score = orderChains(
        plan,
        context.curX,
        context.curY
      ).score;

      if (score < bestScore) {
        bestScore = score;
        bestPlan = plan;
      }
    }

    return bestPlan;
  };

  const drawColor = (
    colorIndex: number,
    components: ComponentPlan[]
  ) => {
    context.comments([
      "",
      '==========================================',
      `开始绘制颜色 ${colorIndex}`,
      `连通块数量: ${components.length}`,
      '=========================================='
    ]);

    const remaining = new Set<ComponentPlan>(components);

    while (remaining.size > 0) {
      let bestComponent: ComponentPlan | null = null;
      let bestDistance = Infinity;

      for (const component of remaining) {
        const distance = distanceToComponent(
          component,
          context.curX,
          context.curY
        );

        if (distance < bestDistance) {
          bestDistance = distance;
          bestComponent = component;
        }
      }

      if (!bestComponent) {
        throw new Error(
          `Failed to find next component for color ${colorIndex}`
        );
      }

      const plan = chooseBestOrientation(bestComponent);
      drawSegmentPlan(plan);
      remaining.delete(bestComponent);
    }

    context.comment(`颜色 ${colorIndex} 全部连通块绘制完成`);
  };

  // ============================================================
  // 开始
  // ============================================================

  const componentsByColor = buildAllColorComponents();

  initToolPanel();
  initColorPanel();

  const colorSize = palette.length + 1;
  let colorBatchStart = 1;

  while (colorBatchStart < colorSize) {
    const colorBatchEnd = Math.min(
      colorBatchStart + 8,
      colorSize - 1
    );

    context.comments([
      "",
      '==========================================',
      `绘制批次: 颜色 ${colorBatchStart} ~ ${colorBatchEnd}`,
      '=========================================='
    ]);

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

    // 保留原来的批次机制；颜色内部按当前光标最近连通块顺序绘制。
    const remainingColors = new Set<number>(presentColors);

    while (remainingColors.size > 0) {
      let bestColor = -1;
      let bestDistance = Infinity;

      for (const colorIndex of remainingColors) {
        const components = componentsByColor.get(colorIndex)!;
        for (const component of components) {
          const distance = distanceToComponent(
            component,
            context.curX,
            context.curY
          );

          if (distance < bestDistance) {
            bestDistance = distance;
            bestColor = colorIndex;
          }
        }
      }

      if (bestColor < 0) {
        break;
      }

      const slot = bestColor - colorBatchStart;

      context.comments([
        "",
        '==========================================',
        `绘制颜色 ${bestColor} (Slot ${slot})`,
        '=========================================='
      ]);

      chooseColorPanel(slot);
      drawColor(
        bestColor,
        componentsByColor.get(bestColor)!
      );

      remainingColors.delete(bestColor);
    }

    colorBatchStart += 9;
  }

  context.comments(["",
    '==========================================',
    "全图绘制完成，复位光标至 (0,0)",
    '=========================================='
  ]);
  moveTo(0, 0);

  return context.lines.join('\n');
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
    goto,
    beginDraw,
    endDraw,
    initToolPanel,
    initColorPanel,
    chooseColorPanel,
    chooseHSVColor,
    moveTo,
    getId,
    manhattanDistance,
    directionFromTo,
  } = context;

  // context.comment('==========================================');
  // context.comment('Tomodachi Life 自动化绘制宏脚本');
  // lines.push('#');
  // context.comment('DFS 路径优化策略：');
  // context.comment('1. 一次扫描整张图，建立每种颜色的 4 邻接连通块');
  // context.comment('2. 一个颜色连通块只绘制一次，完成后才进入下一个连通块');
  // context.comment('3. 连通块内先建立 DFS 生成树，再执行“开放式 DFS”');
  // context.comment('4. 最终路径上的树边只走一次，其余树边走两次');
  // context.comment('5. 因此连通块移动步数从固定的 2(N-1) 降为 2(N-1)-D');
  // context.comment('   其中 D 是 DFS 生成树中入口到最深节点的深度');
  // context.comment('6. 使用低可用度优先（Warnsdorff 风格）尝试多种方向顺序，尽量让 D 更大');
  // context.comment('7. A 按下期间始终只在当前连通块内移动');
  // context.comment('8. 连通块之间仍然 UP A 后再移动');
  // context.comment(`尺寸: ${w}x${h} | 颜色数: ${palette.length} | 延迟: ${delay}ms`);
  // context.comment('==========================================');
  // lines.push('');

  
  context.comments([
    '==========================================',
    'Tomodachi Life 自动化绘制宏脚本',
    'DFS 路径优化策略：',
    '1. 扫描各个颜色的所有连通块',
    '2. 一次性将一种颜色的所有连通块绘制完成, 之后再绘制下一个颜色',
    `尺寸: ${w}x${h} | 颜色数: ${palette.length} | 延迟: ${delay}ms`,
    '==========================================',
    ''
  ]);

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
    const direction = directionFromTo(from, to);
    goto(direction, 1);
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

    beginDraw();

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
      endDraw();
      throw new Error(
        `Optimized DFS path mismatch: ` +
        `path=${finalPath.length}, depth=${tree.depth[deepest]}`
      );
    }

    endDraw();

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

    context.comments(['',
      '==========================================',
      `开始绘制颜色 ${colorIndex}`,
      `连通块数量: ${components.length}`,
      '=========================================='
    ]);

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

    context.comment(`颜色 ${colorIndex} 全部连通块绘制完成`);
  };

  // ============================================================
  // 开始建立所有颜色的 Component
  // ============================================================

  const componentsByColor = buildAllColorComponents();

  initToolPanel();
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

    context.comments(['',
      '==========================================',
      `绘制批次: 颜色 ${colorBatchStart} ~ ${colorBatchEnd}`,
      '=========================================='
    ]);

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

  context.comments(['',
    '==========================================',
    '全图绘制完成，复位光标至 (0,0)',
    '==========================================',
  ]);

  moveTo(0, 0);

  return context.lines.join('\n');
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