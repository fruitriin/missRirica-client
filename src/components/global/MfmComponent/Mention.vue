<template>Mention</template>

<script>
const HOST = "https://misskey.ioo";
export default {
  name: "Mention.vue",
  props: {
    token: Object,
    author: Object,
  },
  data() {
    return {
      key: Math.random(),
      host:
        (this.token.props.host == null &&
        this.author &&
        this.author.host != null
          ? this.author.host
          : this.token.props.host) || HOST,
      username: this.token.props.username,
    };
  },
};
</script>

<style scoped></style>
