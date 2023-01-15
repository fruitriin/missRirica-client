<template>
<MkImageViewer v-if="howto1" :image="{ url: '/client-assets/img/howto1.jpg'}" @close="howto1 = false"/>
<MkImageViewer v-if="howto2" :image="{ url: '/client-assets/img/howto2.jpg'}" @close="howto2 = false"/>
<form
	class="eppvobhk _monolithic_"
	:class="{ signing, totpLogin }"
	@submit.prevent="onSubmit"
>
	<div class="auth _section _formRoot">
		<div class="normal-signin">
			インスタンス
			<Select v-model="instanceUrl" large :model-value="instances[0]?.url">
				<option value="other">自分で入力する</option>
				<option
					v-for="(instance, i) in instances" :key="instance.url" :value="instance.url"
					:selected="i === 0"
				>
					{{ instance.name }}
				</option>
			</Select>
			<template v-if="instanceUrl === 'other'">
				URL
				<MkInput

					v-model="instanceUrlOther"
					:spellcheck="false"
					autofocus
					required
				/>
			</template>


			アクセストークン
			<MkInput
				v-model="token"
				:spellcheck="false"
				autofocus
				required
				data-cy-signin-username
			></MkInput>
			<MkButton
				class="_formBlock"
				type="submit"
				primary
				:disabled="signing"
				style="margin: 0 auto"
			>
				{{ signing ? i18n.ts.loggingIn : i18n.ts.login }}
			</MkButton>
		</div>

		<div style="display: flex; justify-content: center;">
			<a href="https://misskey.io/notes/99l9jqqun2" target="_blank" style="color: var(--link); text-align: center">アクセストークンの作り方</a>
		</div>
	</div>
</form>
</template>

<script lang="ts" setup>
import { defineAsyncComponent } from "vue";
import { toUnicode } from "punycode/";
import MkButton from "@/components/MkButton.vue";
import MkInput from "@/components/form/input.vue";
import MkInfo from "@/components/MkInfo.vue";
import MkMediaImage from "@/components/MkMediaImage.vue";
import MkImageViewer from "@/components/MkImageViewer.vue";
import * as os from "@/os";
import { login } from "@/account";
import { showSuspendedDialog } from "../scripts/show-suspended-dialog";
import { instance } from "@/instance";
import { i18n } from "@/i18n";
import Select from "@/components/form/select.vue";

let signing = $ref(false);
let user = $ref(null);
let username = $ref("");
let password = $ref("");
let token = $ref("");
let totpLogin = $ref(false);
let credential = $ref(null);
let challengeData = $ref(null);
let queryingKey = $ref(false);
let hCaptchaResponse = $ref(null);
let reCaptchaResponse = $ref(null);
const instanceUrl = $ref("")
const instanceUrlOther = $ref("")

const meta = $computed(() => instance);

const howto1 = $ref(false)
const howto2 = $ref(false)

const emit = defineEmits<{
  (ev: "login", v: any): void;
}>();

const props = defineProps({
  withAvatar: {
    type: Boolean,
    required: false,
    default: true,
  },
  autoSet: {
    type: Boolean,
    required: false,
    default: false,
  },
  message: {
    type: String,
    required: false,
    default: "",
  },
});

function onUsernameChange() {
  os.api("users/show", {
    username: username,
  }).then(
    (userResponse) => {
      user = userResponse;
    },
    () => {
      user = null;
    }
  );
}

function onLogin(res: any) {
  if (props.autoSet) {
    return login(res.i, res.instance);
  }
}

const instanceUrlResult = $computed(() => {
  if(instanceUrl === 'other'){
    // うっかりhttps://を入れてもreplaceされるから大丈夫
    // new URL.origin
    return new URL("https://" + instanceUrlOther.replace("https://", "")).origin
  }
  return "https://" + instanceUrl
})

function onSubmit() {
  signing = true;
  console.log("submit");
  if (!token.value) {
    login(token, instanceUrlResult);
    signing = false;
  }
}

function loginFailed(err) {
  switch (err.id) {
    case "6cc579cc-885d-43d8-95c2-b8c7fc963280": {
      os.alert({
        type: "error",
        title: i18n.ts.loginFailed,
        text: i18n.ts.noSuchUser,
      });
      break;
    }
    case "932c904e-9460-45b7-9ce6-7ed33be7eb2c": {
      os.alert({
        type: "error",
        title: i18n.ts.loginFailed,
        text: i18n.ts.incorrectPassword,
      });
      break;
    }
    case "e03a5f46-d309-4865-9b69-56282d94e1eb": {
      showSuspendedDialog();
      break;
    }
    case "22d05606-fbcf-421a-a2db-b32610dcfd1b": {
      os.alert({
        type: "error",
        title: i18n.ts.loginFailed,
        text: i18n.ts.rateLimitExceeded,
      });
      break;
    }
    default: {
      console.log(err);
      os.alert({
        type: "error",
        title: i18n.ts.loginFailed,
        text: JSON.stringify(err),
      });
    }
  }

  challengeData = null;
  totpLogin = false;
  signing = false;
}

function resetPassword() {
  os.popup(
    defineAsyncComponent(() => import("@/components/MkForgotPassword.vue")),
    {},
    {},
    "closed"
  );
}

let instances = $ref([])

fetch("https://instanceapp.misskey.page/instances.json").then(res => {
  res.json().then(data => {
    instances = data.instancesInfos
  })
})

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
