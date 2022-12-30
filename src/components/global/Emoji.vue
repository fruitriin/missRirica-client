<template>
  {{ emoji }}
  <img
    v-if="customEmoji"
    class="mk-emoji custom"
    :class="{ normal, noStyle }"
    :src="url"
    decoding="async"
  />
  <img
    v-else-if="char && !useOsNativeEmojis"
    class="mk-emoji"
    :src="url"
    decoding="async"
  />
  <span v-else-if="char && useOsNativeEmojis">{{ char }}</span>
  <span v-else>{{ emoji }}</span>
</template>

<script>
import { char2filePath } from "~/utils/twimoji-base.ts";
import twemoji from "twemoji-parser";
export default {
  props: {
    emoji: String,
    normal: Boolean,
    noStyle: Boolean,
    customEmoji: Object,
    isReaction: Boolean,
  },
  computed: {
    isCustom() {
      return this.emoji.startsWith(":");
    },
    char() {
      console.log(this.emoji);
      return this.isCustom.value ? null : this.emoji;
    },
    useOsNativeEmojis() {
      return false;
    },
    url() {
      console.log(this.emoji, twemoji.parse(this.emoji));
      return twemoji.parse(this.emoji);
      if (this.char) {
        return char2filePath(this.char);
      } else {
        return this.customEmoji.url;

        // defaultStore.state.disableShowingAnimatedImages
        //   ? getStaticImageUrl(customEmoji.value.url)
        //   : this.customEmoji.value.url;
      }
    },
  },
};
</script>

<style lang="scss" scoped>
.mk-emoji {
  height: 1.25em;
  vertical-align: -0.25em;

  &.custom {
    height: 2.5em;
    vertical-align: middle;
    transition: transform 0.2s ease;

    &:hover {
      transform: scale(1.2);
    }

    &.normal {
      height: 1.25em;
      vertical-align: -0.25em;

      &:hover {
        transform: none;
      }
    }
  }

  &.noStyle {
    height: auto !important;
  }
}
</style>
