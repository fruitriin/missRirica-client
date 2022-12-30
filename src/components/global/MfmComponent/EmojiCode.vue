<template><img :src="emoji()" /></template>

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
      type: Object as PropType<{ emojis: { name: string; url: string }[] }>,
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

<style scoped></style>
