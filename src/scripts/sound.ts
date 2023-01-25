import { ColdDeviceStorage } from '@/store';

const cache = new Map<string, HTMLAudioElement>();

export const soundsTypes = [
	null,
	'syuilo/up',
	'syuilo/down',
	'syuilo/pope1',
	'syuilo/pope2',
	'syuilo/waon',
	'syuilo/popo',
	'syuilo/triple',
	'syuilo/poi1',
	'syuilo/poi2',
	'syuilo/pirori',
	'syuilo/pirori-wet',
	'syuilo/pirori-square-wet',
	'syuilo/square-pico',
	'syuilo/reverved',
	'syuilo/ryukyu',
	'syuilo/kick',
	'syuilo/snare',
	'syuilo/queue-jammed',
	'aisha/1',
	'aisha/2',
	'aisha/3',
	'noizenecio/kick_gaba1',
	'noizenecio/kick_gaba2',
	'noizenecio/kick_gaba3',
	'noizenecio/kick_gaba4',
	'noizenecio/kick_gaba5',
	'noizenecio/kick_gaba6',
	'noizenecio/kick_gaba7',
] as const;


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