interface Decision {
  lineCount: number;
  charCount: number;
  type: 'single' | 'repeat';
  L?: number;
  r?: number;
}

/**
 * 判断是否为 REPEAT 指令行
 */
function isRepeatLine(line: string): boolean {
  const u = line.toUpperCase();
  return u === 'REPEAT' || u.startsWith('REPEAT ') || u.startsWith('REPEAT\t');
}

/**
 * 判断是否为 END 指令行
 */
function isEndLine(line: string): boolean {
  const u = line.toUpperCase();
  return u === 'END' || u.startsWith('END ') || u.startsWith('END\t') || u.startsWith('END#');
}

/**
 * 压缩脚本指令数组，自动识别重复指令块并转换为 REPEAT ... END 循环，同时根据嵌套深度生成缩进
 *
 * @param lines 输入的脚本行数组（包含指令与注释）
 * @param indentUnit 缩进单位，默认为 2 个空格 '  '
 * @param initialDepth 起始缩进深度，默认为 0
 * @param maxDepth 最大允许循环嵌套深度，默认为 8
 * @returns 压缩并格式化缩进后的脚本行数组
 */
export const compressMacro = (
  lines: string[],
  indentUnit: string = '  ',
  initialDepth: number = 0,
  maxDepth: number = 8
): string[] => {
  if (!lines || lines.length === 0) return [];

  const trimmedLines = lines.map((l) => l.trim()).filter(l => l.length > 0 && !l.startsWith("#"));
  const n = trimmedLines.length;

  // 快速判断两段指令块内容是否完全一致
  function areBlocksEqual(start1: number, start2: number, len: number): boolean {
    for (let k = 0; k < len; k++) {
      if (trimmedLines[start1 + k] !== trimmedLines[start2 + k]) {
        return false;
      }
    }
    return true;
  }

  // 范围解缓存 key 增加 currentDepth，格式为 `${start},${end},${depth}`
  const memo = new Map<string, Decision[]>();

  // 阶段 1：深度受限的数值 DP
  function solveRange(start: number, end: number, currentDepth: number): Decision[] {
    const key = `${start},${end},${currentDepth}`;
    if (memo.has(key)) return memo.get(key)!;

    const rangeLen = end - start + 1;
    const dp: Decision[] = new Array(rangeLen + 1);

    dp[rangeLen] = {
      lineCount: 0,
      charCount: 0,
      type: 'single',
    };

    // 预计算当前区间内每一行对应的初始嵌套深度
    const lineDepths = new Array<number>(rangeLen);
    let d = currentDepth;
    for (let k = 0; k < rangeLen; k++) {
      const raw = trimmedLines[start + k];
      if (isEndLine(raw)) {
        d = Math.max(0, d - 1);
      }
      lineDepths[k] = d;
      if (isRepeatLine(raw)) {
        d++;
      }
    }

    for (let i = rangeLen - 1; i >= 0; i--) {
      const globalIdx = start + i;
      const currentLine = trimmedLines[globalIdx];
      const curDepth = lineDepths[i];

      // 默认决策：不压缩当前行
      let best: Decision = {
        lineCount: 1 + dp[i + 1].lineCount,
        charCount: currentLine.length + dp[i + 1].charCount,
        type: 'single',
      };

      // 仅当当前嵌套深度小于 maxDepth 时，才允许尝试合成新的 REPEAT 循环
      if (curDepth < maxDepth) {
        const remainingLen = rangeLen - i;
        const maxL = Math.floor(remainingLen / 2);

        for (let L = 1; L <= maxL; L++) {
          let R = 1;
          while (globalIdx + (R + 1) * L - 1 <= end) {
            if (areBlocksEqual(globalIdx, globalIdx + R * L, L)) {
              R++;
            } else {
              break;
            }
          }

          if (R >= 2) {
            let innerLineCount = 1;
            let innerCharCount = currentLine.length;

            if (L > 1) {
              // 合成 REPEAT 后，内部指令的深度增加 1
              const innerDp = solveRange(globalIdx, globalIdx + L - 1, curDepth + 1);
              innerLineCount = innerDp[0].lineCount;
              innerCharCount = innerDp[0].charCount;
            }

            for (let r = 2; r <= R; r++) {
              const repeatHeaderLen = `REPEAT ${r}`.length;
              const candLineCount = 1 + innerLineCount + 1 + dp[i + r * L].lineCount;
              const candCharCount =
                repeatHeaderLen +
                innerCharCount +
                innerLineCount * indentUnit.length +
                3 + // "END"
                dp[i + r * L].charCount;

              if (
                candLineCount < best.lineCount ||
                (candLineCount === best.lineCount && candCharCount < best.charCount)
              ) {
                best = {
                  lineCount: candLineCount,
                  charCount: candCharCount,
                  type: 'repeat',
                  L,
                  r,
                };
              }
            }
          }
        }
      }

      dp[i] = best;
    }

    memo.set(key, dp);
    return dp;
  }

  // 阶段 2：深度感知回溯构建最终字符串数组
  function reconstruct(start: number, end: number, baseDepth: number): string[] {
    const result: string[] = [];
    let i = 0;
    let currentDepth = baseDepth;
    const rangeLen = end - start + 1;
    const dp = solveRange(start, end, baseDepth);

    while (i < rangeLen) {
      const dec = dp[i];
      const globalIdx = start + i;
      const rawLine = trimmedLines[globalIdx];

      if (dec.type === 'single') {
        if (isEndLine(rawLine)) {
          currentDepth = Math.max(0, currentDepth - 1);
        }

        const indentStr = indentUnit.repeat(currentDepth);
        result.push(indentStr + rawLine);

        if (isRepeatLine(rawLine)) {
          currentDepth++;
        }

        i += 1;
      } else if (dec.type === 'repeat') {
        const L = dec.L!;
        const r = dec.r!;

        const indentStr = indentUnit.repeat(currentDepth);
        result.push(`${indentStr}REPEAT ${r}`);

        // 递归生成内部循环体，深度 +1
        const innerLines = reconstruct(globalIdx, globalIdx + L - 1, currentDepth + 1);
        result.push(...innerLines);

        result.push(`${indentStr}END`);

        i += r * L;
      }
    }

    return result;
  }

  return reconstruct(0, n - 1, initialDepth);
};