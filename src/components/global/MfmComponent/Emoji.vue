<template>
  Emoji
  {{ token }}
  <!--  <span v-html="token"></span>-->
</template>

<script>
export default {
  name: "Emoji.vue",
  props: {
    token: String,
  },
};
</script>

<style scoped></style>
