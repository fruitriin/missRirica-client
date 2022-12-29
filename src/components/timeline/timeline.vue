<template>
  <Note v-for="note in timeline" :key="note.id" :note="note" />
</template>

<script>
import { userStore } from "~/store/UserStore";
import Note from "~/components/timeline/note.vue";

export default {
  components: { Note },
  async setup() {
    const { $state: state, init, api, stream } = userStore();

    const res = await api.request("notes/hybrid-timeline");

    const timeline = ref(res);
    function prepend(res) {
      console.log("prepend", res);
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
