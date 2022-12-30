<template>InlineCode {{ token.code }}</template>

<script>
export default {
  name: "InlineCode.vue",
  props: {
    token: Object,
  },
  data() {
    return {
      inline: true,
    };
  },
};
</script>
