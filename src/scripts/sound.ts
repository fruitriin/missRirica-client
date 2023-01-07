import { ColdDeviceStorage } from "@/store";

const cache = new Map<string,  AudioBuffer>();

const ctx = new AudioContext()


export async function getAudio(file: string, useCache = true) {
  if (useCache && cache.has(file)) {
    return cache.get(file);
  }

  const response = await fetch(`/client-assets/sounds/${file}.mp3`);
  const arrayBuffer = await response.arrayBuffer()
  const audioBuffer = await ctx.decodeAudioData(arrayBuffer)
  if (useCache) cache.set(file, audioBuffer);
  return audioBuffer;
}

export function setVolume(
  audio: HTMLAudioElement,
  volume: number
): HTMLAudioElement {
  const masterVolume = ColdDeviceStorage.get("sound_masterVolume");

  audio.volume = masterVolume - (1 - volume) * masterVolume;
  return audio;
}

export function play(type: string) {
  const sound = ColdDeviceStorage.get(("sound_" + type) as any);
  if (sound.type == null) return;
  playFile(sound.type, sound.volume);
}

export async function playFile(file: string, volume: number) {
  const masterVolume = ColdDeviceStorage.get("sound_masterVolume");
  if (masterVolume === 0) return;

  const soundSource = ctx.createBufferSource()
  soundSource.buffer = await getAudio(file)
  soundSource.connect(ctx.destination)
  soundSource.start()

}
