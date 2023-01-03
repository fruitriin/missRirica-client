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
    plain: true,
    note: Object,
  },
};
</script>

<style scoped></style>
