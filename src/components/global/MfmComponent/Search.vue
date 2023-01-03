<template>
  <div>Search: {{ $attrs.token }}</div>
</template>

<script>
export default {
  props: {
    token: {
      type: Object,
      required: true,
    },
    note: {
      type: Object,
      required: true,
    },
    plain: {
      type: Boolean,
      default: false,
    },
  },
  name: "Search.vue",
};
</script>

<style scoped></style>
