<template>
  <div>
    <avater :user="note.user" /> {{ note.text }}
    <Mfm :text="note.text" :author="note.user" :custom-emojis="note.emojis" />
  </div>
</template>

<script lang="ts">
import { entities } from "misskey-js";
import { PropType } from "vue";
import mfm from "@/components/mfm";
export default {
  name: "note",
  components: {
    mfm,
  },
  props: {
    note: {
      type: Object as PropType<entities.Note>,
    },
  },
};
</script>

<style scoped></style>
