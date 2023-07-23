<script lang="ts">
export default defineNuxtComponent({
  data(){
    return {
      serverUrl: "",
      userId: "",
      password: "",
      accessToken: "",
    }
  },
  methods:{
    login(){
      // ログインリクエスト投げて問題なければstoreへ入れる
    }
  }
})

</script>
<template>
  <Teleport to="body">
    <div>
      サーバーURL
      <input v-model="serverUrl" />
      アクセストークン
      <input v-model="accessToken">
      ユーザーID
      <input v-model="userId" />
      パスワード
      <input v-model="password" type="password" />



      <button @click="login">ログイン</button>
    </div>
  </Teleport>
</template>

<style lang="scss">

</style>
