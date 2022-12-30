<template>
  <template v-for="(t, i) in parsedText">
    <span>{{ t }}</span>
    <br v-if="i !== parsedText.length" />
  </template>
</template>

<script>
/**
 * 完成
 */
export default {
  inheritAttrs: true,
  name: "MfmText",
  props: {
    token: Object,
    plain: {
      type: Boolean,
      default: false,
    },
  },
  computed: {
    parsedText() {
      if (!this.plain) return this.token.text.split(/\r\n|\n|\r/);
      return [this.token.text.replace.replace(/\n/g, " ")];
    },
  },
};
</script>
