<template>
  <div v-if="!loggedIn">
    <h1>MissRirica</h1>
    <div>
      MissRiricaはMisskeyクライアントです。
    </div>
    <div>
    <label>
      サーバー名
      <input v-model="serverHost" placeholder="https://misskey.example.com/" />

    </label>
    </div>

    <div>
    <label>
      アカウント名
      <input v-model="userName" />

    </label>
    </div>
    <div>
    <label for="">アクセストークン
    <input v-model="accessToken"  type="password" />
    </label>
    </div>
    <div>
    <input type="checkbox"><a href="https://riinswork.space/missRirica/privacy/" >MissRirica 利用規約 & プライバシーポリシー</a>
    </div>
    <button @click="signIn">ろぐいん！</button>
    <pre>{{ account }}</pre>
    <pre>{{  debug }}</pre>
    <img src="@@/assets/ririca.png">
  </div>
</template>

<script>
import { api as misskeyApi } from 'misskey-js';


export default {
  mounted(){
    if(localStorage.getItem("account")) this.activateMisskeyV13()
  },
  data(){
    return {
      i18n: {
        ts: {}
      },
      serverHost: "",
      userName: "",
      accessToken: "",
      account: {},
      loggedIn: false,
      debug: {},
    }
  },
  methods:{
    signIn(){
      const url = "https://" + this.serverHost.replace("https://", "").replace("http://", "").split("/")[0];


      const cli = new misskeyApi.APIClient({
        origin: this.serverHost,
        credential: this.accessToken,
      });

      cli.request("i").then((res) => {
        this.account = res

        localStorage.setItem("account", JSON.stringify({...res, token: this.accessToken, instanceUrl: url}))
        this.activateMisskeyV13()
      }).catch((e) => {
        this.debug = e
      })

    },
    activateMisskeyV13(){
      const misskeyV13 = document.createElement("script")
      misskeyV13.setAttribute("src", "misskey-v13/app.js")
      misskeyV13.setAttribute("type", "module")
      const misskeyV13Style = document.createElement("link")
      misskeyV13Style.setAttribute("rel", "stylesheet" )
      misskeyV13Style.setAttribute("href", "misskey-v13/init.css")
      document.head.appendChild(misskeyV13)
      document.head.appendChild(misskeyV13Style)
      this.loggedIn = true
    }
  },
}
</script>


<style lang="scss" scoped>
.eppvobhk {
  > .auth {
    > .avatar {
      margin: 0 auto 0 auto;
      width: 64px;
      height: 64px;
      background: #ddd;
      background-position: center;
      background-size: cover;
      border-radius: 100%;
    }
  }
}
</style>
