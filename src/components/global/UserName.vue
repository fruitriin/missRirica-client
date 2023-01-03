<template>
  <MfmComponent :text="user.name || user.username" :plain="true" :note="user" />
</template>

<script lang="ts">
import * as misskey from "misskey-js";

export default defineComponent({
  props: {
    user: Object,
    nowrap: {
      // 今の所つかってない
      type: Boolean,
      default: true,
    },
    plain: {
      type: Boolean,
      default: false,
    },
    note: Object,
  },
});
</script>
