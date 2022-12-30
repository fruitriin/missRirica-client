<template><a href="token.url" v-text="token.url"></a></template>

<script>
export default {
  name: "Url.vue",
  props: {
    token: Object,
  },
};
</script>

<style scoped></style>
