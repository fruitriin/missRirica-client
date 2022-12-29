<template>
  <div :class="{ cat: user.isCat }" class="avatar">
    <img class="inner" :src="user.avatarUrl" decoding="async" />
  </div>
</template>

<script lang="ts">
import { entities } from "misskey-js";
import { PropType } from "nuxt/dist/app/compat/capi";

export default defineComponent({
  props: {
    user: Object as PropType<entities.User>,
  },
});
</script>

<style lang="scss">
@keyframes cat_left {
  from {
    transform: rotate(37.6deg) skew(30deg);
  }
  25% {
    transform: rotate(10deg) skew(30deg);
  }
  50% {
    transform: rotate(20deg) skew(30deg);
  }
  75% {
    transform: rotate(0deg) skew(30deg);
  }
  to {
    transform: rotate(37.6deg) skew(30deg);
  }
}

@keyframes cat_right {
  from {
    transform: rotate(-37.6deg) skew(-30deg);
  }
  30% {
    transform: rotate(-10deg) skew(-30deg);
  }
  55% {
    transform: rotate(-20deg) skew(-30deg);
  }
  75% {
    transform: rotate(0deg) skew(-30deg);
  }
  to {
    transform: rotate(-37.6deg) skew(-30deg);
  }
}

.avatar {
  position: relative;
  display: inline-block;
  vertical-align: bottom;
  flex-shrink: 0;
  border-radius: 100%;
  line-height: 16px;
  flex-shrink: 0;
  display: inline-block;
  width: 28px;
  height: 28px;
  margin: 0 8px 0 0;
  border-radius: 6px;

  > .inner {
    position: absolute;
    bottom: 0;
    left: 0;
    right: 0;
    top: 0;
    border-radius: 100%;
    z-index: 1;
    overflow: hidden;
    object-fit: cover;
    width: 100%;
    height: 100%;
  }

  > .indicator {
    position: absolute;
    z-index: 1;
    bottom: 0;
    left: 0;
    width: 20%;
    height: 20%;
  }

  &.square {
    border-radius: 20%;

    > .inner {
      border-radius: 20%;
    }
  }

  &.cat {
    &:before,
    &:after {
      background: #df548f;
      border: solid 4px currentColor;
      box-sizing: border-box;
      content: "";
      display: inline-block;
      height: 50%;
      width: 50%;
    }

    &:before {
      border-radius: 0 75% 75%;
      transform: rotate(37.5deg) skew(30deg);
    }

    &:after {
      border-radius: 75% 0 75% 75%;
      transform: rotate(-37.5deg) skew(-30deg);
    }

    &:hover {
      &:before {
        animation: cat_left 1s infinite;
      }

      &:after {
        animation: cat_right 1s infinite;
      }
    }
  }
}
</style>
