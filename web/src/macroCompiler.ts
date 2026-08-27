// ============================================================================
// 1. 枚举与常量定义
// ============================================================================

export const CommandTag = {
  end: 0x00,
  up: 0x01,
  down: 0x02,
  tap: 0x03,
  stick: 0x04,
  up_combine: 0x05,
  down_combine: 0x06,
  tap_combine: 0x07,
  reset_stick: 0x21,
  reset_button: 0x22,
  reset_all: 0x23,
  wait: 0x41,
  wait_u8: 0x42,
  wait_u16: 0x43,
  repeat: 0x61,
  repeat_u16: 0x62,
  repeat_u8: 0x63,
  commands: 0x81,
}
export type CommandTag = (typeof CommandTag)[keyof typeof CommandTag];

export const StickType = {
  left_stick: 0x01,
  right_stick: 0x02,
}
export type StickType = (typeof StickType)[keyof typeof StickType];

// Upper 按键映射 (base 0x80)
const BUTTON_UPPER: Record<string, number> = {
  Y: 0x80 | 0,
  X: 0x80 | 1,
  B: 0x80 | 2,
  A: 0x80 | 3,
  JCL_SR: 0x80 | 4,
  JCL_SL: 0x80 | 5,
  R: 0x80 | 6,
  ZR: 0x80 | 7,
};

// Shared 按键映射 (base 0x40)
const BUTTON_SHARED: Record<string, number> = {
  PLUS: 0x40 | 0,
  MINUS: 0x40 | 1,
  R_STICK_PRESSED: 0x40 | 2,
  L_STICK_PRESSED: 0x40 | 3,
  HOME: 0x40 | 4,
  CAPTURE: 0x40 | 5,
};

// Lower 按键映射 (base 0x00)
const BUTTON_LOWER: Record<string, number> = {
  DPAD_DOWN: 0x00 | 0,
  DPAD_UP: 0x00 | 1,
  DPAD_RIGHT: 0x00 | 2,
  DPAD_LEFT: 0x00 | 3,
  JCR_SR: 0x00 | 4,
  JCR_SL: 0x00 | 5,
  L: 0x00 | 6,
  ZL: 0x00 | 7,
};

const ALL_BUTTONS: Record<string, number> = {
  ...BUTTON_UPPER,
  ...BUTTON_SHARED,
  ...BUTTON_LOWER,
};

// ============================================================================
// 2. 指令 AST 类型定义
// ============================================================================

export type Command =
  | { tag: 'wait' | 'wait_u16' | 'wait_u8'; ms: number }
  | { tag: 'down' | 'down_combine'; buttonByte: number; combine: boolean }
  | { tag: 'up' | 'up_combine'; buttonByte: number; combine: boolean }
  | { tag: 'stick'; stick: StickType; x: number; y: number }
  | { tag: 'reset_stick'; stick: StickType }
  | { tag: 'reset_button' }
  | { tag: 'reset_all' }
  | { tag: 'repeat'; times: number; commands: Command[] }
  | { tag: 'end' };

// ============================================================================
// 3. 解析器辅助函数
// ============================================================================

export function stringToButtonByte(btnName: string): number | null {
  return ALL_BUTTONS[btnName.toUpperCase()] ?? null;
}

export function stringToStick(stickName: string): StickType | null {
  const lower = stickName.toLowerCase();
  if (lower === 'left_stick') return StickType.left_stick;
  if (lower === 'right_stick') return StickType.right_stick;
  return null;
}

export function parseTimeString(str: string): number {
  if (!str || str.length === 0) {
    throw new Error('WrongTimeNumber');
  }

  const match = str.match(/^([0-9.]+)?([a-zA-Z]*)$/);
  if (!match) throw new Error('WrongTimeNumber');

  const numStr = match[1];
  const unitStr = (match[2] || 'ms').toLowerCase();
  const num = numStr ? parseFloat(numStr) : 0;

  if (isNaN(num)) throw new Error('WrongTimeNumber');

  let multiplier = 1;
  switch (unitStr) {
    case 'ms':
    case '':
      multiplier = 1;
      break;
    case 's':
      multiplier = 1000;
      break;
    case 'm':
      multiplier = 60 * 1000;
      break;
    case 'h':
      multiplier = 60 * 60 * 1000;
      break;
    default:
      throw new Error('WrongTimeUnit');
  }

  return Math.round(num * multiplier) >>> 0;
}

function parseStickCoord(str: string): number {
  const val = parseFloat(str);
  if (isNaN(val)) throw new Error('InvalidStickValue');
  // 归一化浮点数范围 [-1.0, 1.0] 转换为 signed i8 (-128..127)
  if (str.includes('.')) {
    return Math.round(val * (val >= 0 ? 127 : 128));
  }
  return Math.max(-128, Math.min(127, Math.round(val)));
}

// ============================================================================
// 4. 指令解析与优化 (合并 WAIT 与 消除连续重复 RESET)
// ============================================================================

function createWaitCommand(ms: number): Command {
  if (ms <= 0xff) {
    return { tag: 'wait_u8', ms };
  } else if (ms <= 0xffff) {
    return { tag: 'wait_u16', ms };
  } else {
    return { tag: 'wait', ms };
  }
}

function isWaitCommand(cmd: Command): boolean {
  return cmd.tag === 'wait' || cmd.tag === 'wait_u8' || cmd.tag === 'wait_u16';
}

function appendCommand(commands: Command[], command: Command): void {
  if (
    command.tag === 'reset_all' ||
    command.tag === 'reset_button' ||
    command.tag === 'reset_stick'
  ) {
    // 消除尾部连续相同的复位指令 (对齐 Zig 的 eraseTailSameCommand)
    while (commands.length > 0) {
      const last = commands[commands.length - 1];
      if (last.tag !== command.tag) break;

      // 当两者均为 reset_stick 时，需额外校验摇杆类型是否一致
      if (last.tag === 'reset_stick' && command.tag === 'reset_stick') {
        if (last.stick !== command.stick) break;
      }

      commands.pop();
    }
    commands.push(command);
  } else if (isWaitCommand(command)) {
    // 连续 WAIT 时间叠加合并
    let totalMs = (command as { ms: number }).ms;
    while (commands.length > 0) {
      const last = commands[commands.length - 1];
      if (isWaitCommand(last)) {
        totalMs += (last as { ms: number }).ms;
        commands.pop();
      } else {
        break;
      }
    }
    if (totalMs > 0) {
      commands.push(createWaitCommand(totalMs));
    }
  } else {
    commands.push(command);
  }
}

function parseCommandLine(line: string): Command[] | null {
  const trimmed = line.trim();
  if (trimmed.length === 0 || trimmed.startsWith('#')) {
    return null;
  }

  const tokens = trimmed.split(/\s+/);
  const cmdStr = tokens[0].toLowerCase();
  const args = tokens.slice(1);

  switch (cmdStr) {
    case 'wait':
    case 'wait_u8':
    case 'wait_u16': {
      if (args.length < 1) throw new Error('MissingArgument');
      const ms = parseTimeString(args[0]);
      if (ms === 0) return [];
      return [createWaitCommand(ms)];
    }

    case 'down':
    case 'down_combine': {
      if (args.length < 1) throw new Error('MissingArgument');
      const activeCombine = cmdStr === 'down_combine';
      return args.map((arg, i) => {
        const btnByte = stringToButtonByte(arg);
        if (btnByte === null) throw new Error(`UnknownButton: ${arg}`);
        const combine = activeCombine && i + 1 < args.length;
        return {
          tag: combine ? 'down_combine' : 'down',
          buttonByte: btnByte,
          combine,
        };
      });
    }

    case 'up':
    case 'up_combine': {
      if (args.length < 1) throw new Error('MissingArgument');
      const activeCombine = cmdStr === 'up_combine';
      return args.map((arg, i) => {
        const btnByte = stringToButtonByte(arg);
        if (btnByte === null) throw new Error(`UnknownButton: ${arg}`);
        const combine = activeCombine && i + 1 < args.length;
        return {
          tag: combine ? 'up_combine' : 'up',
          buttonByte: btnByte,
          combine,
        };
      });
    }

    case 'tap':
    case 'tap_combine': {
      if (args.length < 3) throw new Error('MissingArgument');
      const down_duration = parseTimeString(args[0]);
      const up_duration = parseTimeString(args[1]);
      const btnTokens = args.slice(2);
      const activeCombine = cmdStr === 'tap_combine';

      const downs: Command[] = [];
      const ups: Command[] = [];

      btnTokens.forEach((arg, i) => {
        const btnByte = stringToButtonByte(arg);
        if (btnByte === null) throw new Error(`UnknownButton: ${arg}`);
        const combine = activeCombine && i + 1 < btnTokens.length;
        downs.push({
          tag: combine ? 'down_combine' : 'down',
          buttonByte: btnByte,
          combine,
        });
        ups.push({
          tag: combine ? 'up_combine' : 'up',
          buttonByte: btnByte,
          combine,
        });
      });

      return [...downs, createWaitCommand(down_duration), ...ups, createWaitCommand(up_duration)];
    }

    case 'stick': {
      if (args.length < 3) throw new Error('MissingArgument');
      const stick = stringToStick(args[0]);
      if (stick === null) throw new Error('UnknownStick');
      const x = parseStickCoord(args[1]);
      const y = parseStickCoord(args[2]);
      return [{ tag: 'stick', stick, x, y }];
    }

    case 'reset_stick': {
      if (args.length < 1) throw new Error('MissingArgument');
      const stick = stringToStick(args[0]);
      if (stick === null) throw new Error('UnknownStick');
      return [{ tag: 'reset_stick', stick }];
    }

    case 'reset_button':
      return [{ tag: 'reset_button' }];

    case 'reset_all':
      return [{ tag: 'reset_all' }];

    case 'repeat': {
      if (args.length < 1) throw new Error('MissingArgument');
      const times = parseInt(args[0], 10);
      if (isNaN(times) || times < 0) throw new Error('InvalidArgument');
      return [{ tag: 'repeat', times, commands: [] }];
    }

    case 'end':
      return [{ tag: 'end' }];

    default:
      throw new Error(`UnknownCommand: ${cmdStr}`);
  }
}

function parseCommandBlock(lines: string[], cursor: { index: number }): Command[] {
  const result: Command[] = [];

  while (cursor.index < lines.length) {
    const line = lines[cursor.index++];
    const cmds = parseCommandLine(line);
    if (!cmds) continue;

    let stopBlock = false;
    for (const cmd of cmds) {
      if (cmd.tag === 'end') {
        stopBlock = true;
        break;
      } else if (cmd.tag === 'repeat') {
        const innerCommands = parseCommandBlock(lines, cursor);
        appendCommand(result, {
          tag: 'repeat',
          times: cmd.times,
          commands: innerCommands,
        });
      } else {
        appendCommand(result, cmd);
      }
    }

    if (stopBlock) break;
  }

  return result;
}

export function parseScript(script: string): Command[] | null {
  const lines = script.split(/\r?\n/);
  const cursor = { index: 0 };
  const commands = parseCommandBlock(lines, cursor);
  return commands.length > 0 ? commands : null;
}

// ============================================================================
// 5. 字节码编译器 (Compiler)
// ============================================================================

class ByteWriter {
  private buffer: number[] = [];

  public writeByte(val: number): void {
    this.buffer.push(val & 0xff);
  }

  public writeUint16LE(val: number): void {
    this.buffer.push(val & 0xff);
    this.buffer.push((val >> 8) & 0xff);
  }

  public writeUint32LE(val: number): void {
    this.buffer.push(val & 0xff);
    this.buffer.push((val >> 8) & 0xff);
    this.buffer.push((val >> 16) & 0xff);
    this.buffer.push((val >> 24) & 0xff);
  }

  public writeInt8(val: number): void {
    this.writeByte((val < 0 ? val + 256 : val) & 0xff);
  }

  public toUint8Array(): Uint8Array {
    return new Uint8Array(this.buffer);
  }
}

function compileCommand(writer: ByteWriter, cmd: Command): void {
  switch (cmd.tag) {
    case 'wait':
      writer.writeByte(CommandTag.wait);
      writer.writeUint32LE(cmd.ms);
      break;
    case 'wait_u16':
      writer.writeByte(CommandTag.wait_u16);
      writer.writeUint16LE(cmd.ms);
      break;
    case 'wait_u8':
      writer.writeByte(CommandTag.wait_u8);
      writer.writeByte(cmd.ms);
      break;

    case 'down':
      writer.writeByte(CommandTag.down);
      writer.writeByte(cmd.buttonByte);
      break;
    case 'down_combine':
      writer.writeByte(CommandTag.down_combine);
      writer.writeByte(cmd.buttonByte);
      break;

    case 'up':
      writer.writeByte(CommandTag.up);
      writer.writeByte(cmd.buttonByte);
      break;
    case 'up_combine':
      writer.writeByte(CommandTag.up_combine);
      writer.writeByte(cmd.buttonByte);
      break;

    case 'stick':
      writer.writeByte(CommandTag.stick);
      writer.writeByte(cmd.stick);
      writer.writeInt8(cmd.x);
      writer.writeInt8(cmd.y);
      break;

    case 'reset_stick':
      writer.writeByte(CommandTag.reset_stick);
      writer.writeByte(cmd.stick);
      break;

    case 'reset_button':
      writer.writeByte(CommandTag.reset_button);
      break;

    case 'reset_all':
      writer.writeByte(CommandTag.reset_all);
      break;

    case 'repeat': {
      if (cmd.times <= 0xff) {
        writer.writeByte(CommandTag.repeat_u8);
        writer.writeByte(cmd.times);
      } else if (cmd.times <= 0xffff) {
        writer.writeByte(CommandTag.repeat_u16);
        writer.writeUint16LE(cmd.times);
      } else {
        writer.writeByte(CommandTag.repeat);
        writer.writeUint32LE(cmd.times);
      }
      compileCommandsBlock(writer, cmd.commands);
      break;
    }

    case 'end':
      writer.writeByte(CommandTag.end);
      break;
  }
}

function compileCommandsBlock(writer: ByteWriter, commands: Command[]): void {
  writer.writeByte(CommandTag.commands);
  for (const cmd of commands) {
    compileCommand(writer, cmd);
  }
  writer.writeByte(CommandTag.end);
}

/** 编译脚本文本为 Uint8Array 二进制字节码 */
export function compile(script: string, endian: 'little' | 'big' = 'little'): Uint8Array | null {
  const commands = parseScript(script);
  if (!commands || commands.length === 0) return null;

  const writer = new ByteWriter();
  // 1 表示 Little-Endian, 0 表示 Big-Endian
  writer.writeByte(endian === 'little' ? 1 : 0);
  compileCommandsBlock(writer, commands);

  return writer.toUint8Array();
}

/** 编译并输出 16 进制字符串 */
export function compileToHex(script: string): string | null {
  const bytecode = compile(script);
  if (!bytecode) return null;
  return Array.from(bytecode)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * 将 Uint8Array 字节数组转换为 URL-Safe Base64 字符串
 * @param bytes 字节数组
 * @param padding 是否保留末尾的 '=' 填充符，默认为 false (不保留)
 */
export function bytesToUrlSafeBase64(bytes: Uint8Array, padding = false): string {
  let binary = '';
  const len = bytes.byteLength;
  
  // 1. 转为 Byte 字符流
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }

  // 2. 使用标准 btoa 编码后，替换 URL 敏感字符
  let base64 = btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

  // 3. 根据配置决定是否去除末尾填充符 '='
  if (!padding) {
    base64 = base64.replace(/=+$/, '');
  }

  return base64;
}

/** 编译并输出 URL-Safe Base64 字符串 */
export function compileToBase64(script: string, padding = true): string | null {
  const bytecode = compile(script);
  if (!bytecode) return null;
  return bytesToUrlSafeBase64(bytecode, padding);
}

/**
 * 格式化毫秒数为友好时间字符串 (例如: 1小时23分45秒 / 500毫秒)
 */
export function formatDuration(totalMs: number): string {
  if (totalMs <= 0) return '0秒';

  const hours = Math.floor(totalMs / (1000 * 60 * 60));
  const minutes = Math.floor((totalMs % (1000 * 60 * 60)) / (1000 * 60));
  const seconds = Math.floor((totalMs % (1000 * 60)) / 1000);
  const ms = totalMs % 1000;

  const parts: string[] = [];
  if (hours > 0) parts.push(`${hours}小时`);
  if (minutes > 0) parts.push(`${minutes}分`);
  if (seconds > 0) parts.push(`${seconds}秒`);
  if (ms > 0) parts.push(`${ms}毫秒`);

  return parts.join('');
}

/**
 * 解析编译后的字节码，计算所有 wait 指令的总等待时间
 * @param bytecode 编译出的 Uint8Array 字节码
 * @returns 包含总毫秒数和友好的时间格式化字符串
 */
export function calculateBytecodeWaitTime(bytecode: Uint8Array): { totalMs: number; formatted: string } {
  if (!bytecode || bytecode.length < 2) {
    return { totalMs: 0, formatted: '0秒' };
  }

  // 字节 0 指定大小端: 1 表示 Little-Endian, 0 表示 Big-Endian
  const isLittleEndian = bytecode[0] === 1;
  const view = new DataView(bytecode.buffer, bytecode.byteOffset, bytecode.byteLength);
  let offset = 1;

  function parseBlock(): number {
    let blockMs = 0;

    // 检查并跳过块起始标记 CommandTag.commands (0x81)
    if (offset < bytecode.length && bytecode[offset] === CommandTag.commands) {
      offset++;
    }

    while (offset < bytecode.length) {
      const tag = bytecode[offset++];

      // 遇 CommandTag.end (0x00) 则结束当前块解析
      if (tag === CommandTag.end) {
        break;
      }

      switch (tag) {
        // 单字节参数指令 (按键/摇杆重置等)
        case CommandTag.up: // up
        case CommandTag.down: // down
        case CommandTag.up_combine: // up_combine
        case CommandTag.down_combine: // down_combine
        case CommandTag.reset_stick: // reset_stick
          offset += 1;
          break;

        // 3 字节参数指令
        case CommandTag.stick: // stick (stickType: 1B, x: 1B, y: 1B)
          offset += 3;
          break;

        // 无参数指令
        case CommandTag.reset_button: // reset_button
        case CommandTag.reset_all: // reset_all
          break;

        // Wait 时间统计指令
        case CommandTag.wait: { // wait (uint32)
          const ms = view.getUint32(offset, isLittleEndian);
          blockMs += ms;
          offset += 4;
          break;
        }
        case CommandTag.wait_u8: { // wait_u8 (uint8)
          const ms = view.getUint8(offset);
          blockMs += ms;
          offset += 1;
          break;
        }
        case CommandTag.wait_u16: { // wait_u16 (uint16)
          const ms = view.getUint16(offset, isLittleEndian);
          blockMs += ms;
          offset += 2;
          break;
        }

        // Repeat 循环嵌套处理
        case CommandTag.repeat: { // repeat (uint32 times)
          const times = view.getUint32(offset, isLittleEndian);
          offset += 4;
          const innerMs = parseBlock();
          blockMs += innerMs * times;
          break;
        }
        case CommandTag.repeat_u16: { // repeat_u16 (uint16 times)
          const times = view.getUint16(offset, isLittleEndian);
          offset += 2;
          const innerMs = parseBlock();
          blockMs += innerMs * times;
          break;
        }
        case CommandTag.repeat_u8: { // repeat_u8 (uint8 times)
          const times = view.getUint8(offset);
          offset += 1;
          const innerMs = parseBlock();
          blockMs += innerMs * times;
          break;
        }

        default:
          break;
      }
    }

    return blockMs;
  }

  const totalMs = parseBlock();

  return {
    totalMs,
    formatted: formatDuration(totalMs),
  };
}