import { Preferences } from "@capacitor/preferences";
async function set(key: string, value: any) {
  await Preferences.set({ key, value: JSON.stringify(value) });
}

async function get(key: string, def?: any) {
  const res = await Preferences.get({ key });
  if (!res) return def;
  return JSON.parse(res.value);
}

async function remove(key: string) {
  await Preferences.remove({ key });
}

export const Pref = {
  set,
  get,
  remove,
};
