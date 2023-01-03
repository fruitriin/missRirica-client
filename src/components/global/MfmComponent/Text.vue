<template>
  <template v-for="(t, i) in parsedText">
    <span>{{ t }}</span>
    <br v-if="showBr(t, i)" />
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
    nowrap: {
      type: Boolean,
      default: false,
    },
    note: Object,
  },
  methods: {
    showBr(text, index) {
      // 行末では改行しない
      if (index + 1 === this.parsedText.length) {
        return false;
      }

      return true;
    },
  },
  computed: {
    parsedText() {
      if (!this.plain) return this.token.text.split(/\r\n|\n|\r/);
      return [this.token.text.replace(/\n/g, " ")];
    },
  },
};
</script>
