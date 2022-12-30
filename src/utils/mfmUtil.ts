import { MfmNode, parse, parseSimple } from "mfm-js";

export function mfm(text: string, plain: boolean): MfmNode[] {
  if (text == null || text === "") {
    return [];
  }
  const ast = plain ? parseSimple(text) : parse(text, { fnNameList: MFM_TAGS });
  return ast;
}

export function getComponent(string: string) {
  return string.replace(/(^.)(.*)/, ($1, $2, $3) => `${$2.toUpperCase() + $3}`);
}

const MFM_TAGS = [
  "tada",
  "jelly",
  "twitch",
  "shake",
  "spin",
  "jump",
  "bounce",
  "flip",
  "x2",
  "x3",
  "x4",
  "font",
  "blur",
  "rainbow",
  "sparkle",
  "rotate",
];
