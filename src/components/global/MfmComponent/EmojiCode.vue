<template><img class="emoji" :src="emoji()" /></template>

<script lang="ts">
import { entities } from "misskey-js";
import { PropType } from "vue";

export default defineComponent({
  name: "EmojiCode.vue",
  props: {
    token: {
      required: true,
    },
    note: {
      type: Object,
      required: true,
    },
  },
  methods: {
    emoji(): string {
      return this.note.emojis.find((e) => {
        return e.name == this.token.name;
      }).url;
    },
  },
});
</script>

<style scoped>
.emoji {
  height: 1.25em;
  vertical-align: -0.25em;
}
</style>
