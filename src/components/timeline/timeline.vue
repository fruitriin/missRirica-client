<template>
  <div>
    <div v-for="note in timeline">
      <Note :note="note" />
    </div>
  </div>
</template>

<script>
import { useUser } from "~/store/useUser";
import Note from "~/components/timeline/note.vue";

export default {
  components: { Note },
  async setup() {
    const { $state: state, init } = useUser();

    const res = await state.api.request("notes/hybrid-timeline");

    const timeline = ref(res);
    function prepend(res) {
      console.log("prepend", res);
      timeline.value.unshift(res);
    }

    const connection = state.stream.useChannel("hybridTimeline");
    connection.on("note", prepend);

    return {
      state,
      timeline,
    };
  },
};
</script>

<style lang="scss" scoped></style>
