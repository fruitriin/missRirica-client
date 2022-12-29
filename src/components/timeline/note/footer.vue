<template>
  <div class="note-footer">
    <!--          <XReactionsViewer ref="reactionsViewer" :note="appearNote" />-->
    <button class="button _button" @click="reply()">
      <ArrowBackIcon />
      <p v-if="note.repliesCount > 0" class="count">
        {{ note.repliesCount }}
      </p>
    </button>
    <button
      v-if="note.canRenote"
      ref="buttonRef"
      class="renote _button canRenote"
      @click="renote()"
    >
      <RecycleIcon />
      <p v-if="note.count > 0" class="count">{{ note.count }}</p>
    </button>
    <button v-else class="renote _button">
      <BanIcon />
    </button>
    <button
      v-if="note.myReaction == null"
      ref="reactButton"
      class="button _button"
    >
      <PlusIcon />
    </button>
    <button
      v-if="note.myReaction != null"
      ref="reactButton"
      class="button _button reacted"
    >
      <MinusIcon />
    </button>
    <button class="button _button">
      <DotsIcon />
    </button>
  </div>
</template>

<script lang="ts">
import { entities } from "misskey-js";
import { PropType } from "vue";
import {
  PlusIcon,
  MinusIcon,
  DotsIcon,
  ArrowBackIcon,
  BanIcon,
  RecycleIcon,
} from "vue-tabler-icons";

export default defineComponent({
  components: {
    MinusIcon,
    DotsIcon,
    PlusIcon,
    ArrowBackIcon,
    BanIcon,
    RecycleIcon,
  },
  props: {
    note: {
      type: Object as PropType<entities.Note>,
      required: true,
    },
  },
});
</script>

<style lang="scss" scoped>
.note-footer {
  > .button {
    margin: 0;
    padding: 8px;
    opacity: 0.7;

    &:not(:last-child) {
      margin-right: 28px;
    }

    .renote {
      display: inline-block;
      height: 32px;
      margin: 2px;
      padding: 0 6px;
      border-radius: 4px;

      &:not(.canRenote) {
        cursor: default;
      }

      &.renoted {
        background: var(--accent);
      }

      > .count {
        display: inline;
        margin-left: 8px;
        opacity: 0.7;
      }
    }

    &:hover {
      color: var(--fgHighlighted);
    }

    > .count {
      display: inline;
      margin: 0 0 0 8px;
      opacity: 0.7;
    }

    &.reacted {
      color: var(--accent);
    }
  }
}
</style>
