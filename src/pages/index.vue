<script lang="ts">
import { useStateStore } from "~/store/globalState";


export default defineNuxtComponent({
  setup(){
    const { $state } = useStateStore()

    return {
      state: $state
    }
  },
  mounted(){
    if(Object.keys(this.state.users).length === 0){
      this.$router.replace("/ririca")
    }
  }
})

</script>

<template>
  <div>
    yehhhh
  </div>
</template>

<style lang="scss">

</style>
