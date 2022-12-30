<template>
  {{ token.emoji }}
</template>

<script>
export default {
  name: "MfmComponentUnicodeEmoji",
  props: {
    token: Object,
    customEmojis: Array,
    normal: Boolean,
  },
};
</script>

<style scoped></style>
