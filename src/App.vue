<template>
  <router-view />
  <loginModal v-if="eventBus.$state.modalControl.login" />
</template>

<script lang="ts">
import { useRiricaStateStore } from "~/store/globalState";

export default defineNuxtComponent({
  setup(){
    const eventBus = useRiricaStateStore()
    return {
      eventBus
    }
  },
})

</script>
