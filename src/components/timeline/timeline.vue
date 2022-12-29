<template>
  <TimelineNote v-for="note in timeline" :key="note.id" :note="note" />
  <TabMenu />
</template>

<script>
import { userStore } from "~/store/UserStore";

export default {
  async setup() {
    const { api, stream } = userStore();

    const res = await api.request("notes/hybrid-timeline");

    const timeline = ref(res);
    function prepend(res) {
      timeline.value.unshift(res);
    }

    const connection = stream.useChannel("hybridTimeline");
    connection.on("note", prepend);

    return {
      timeline,
    };
  },
};
</script>

<style lang="scss" scoped></style>
