import * as Misskey from "misskey-js";
import { markRaw } from "vue";
import { $i } from "@/account";

export const stream = markRaw(
  new Misskey.Stream(
    $i.instanceUrl,
    $i
      ? {
          token: $i.token,
        }
      : null
  )
);
