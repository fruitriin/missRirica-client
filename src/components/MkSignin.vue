<template>
<form class="eppvobhk" :class="{ signing }" @submit.prevent="onSubmit">
	<div class="normal-signin">
		{{ i18n.ts.ririca.instance }}
		<MkSelect v-model="instanceUrl" large model-value="misskey.io">
			<option key="misskey.io" value="misskey.io" :selected="true">
				Misskey.io
			</option>
			<option value="other">
				{{ i18n.ts.ririca.selectInstanceYourself }}
			</option>
		</MkSelect>
		<template v-if="instanceUrl === 'other'">
			URL
			<MkInput
				v-model="instanceUrlOther"
				:spellcheck="false"
				autofocus
				required
			/>
		</template>
		{{ i18n.ts.ririca.accessToken }}
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
</form>
</template>

<script lang="ts" setup>
import { defineAsyncComponent } from "vue";
import { toUnicode } from "punycode/";
import { showSuspendedDialog } from "../scripts/show-suspended-dialog";
import MkButton from "@/components/MkButton.vue";
import MkInput from "@/components/MkInput.vue";
import MkInfo from "@/components/MkInfo.vue";
import MkSelect from "@/components/MkSelect.vue";
import { byteify, hexify } from "@/scripts/2fa";
import * as os from "@/os";
import { login } from "@/account";
import { instance } from "@/instance";
import { i18n } from "@/i18n";

let signing = $ref(false);
let user = $ref(null);
let username = $ref("");
let password = $ref("");
let token = $ref("");
let credential = $ref(null);
let challengeData = $ref(null);
let queryingKey = $ref(false);
let hCaptchaResponse = $ref(null);
let reCaptchaResponse = $ref(null);

const instanceUrl = $ref("");
const instanceUrlOther = $ref("");

const meta = $computed(() => instance);

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
  if (instanceUrl === "other") {
    // うっかりhttps://を入れてもreplaceされるから大丈夫
    // new URL.origin
    return new URL("https://" + instanceUrlOther.replace("https://", ""))
      .origin;
  }
  return "https://" + instanceUrl;
});
function queryKey() {
  queryingKey = true;
  return navigator.credentials
    .get({
      publicKey: {
        challenge: byteify(challengeData.challenge, "base64"),
        allowCredentials: challengeData.securityKeys.map((key) => ({
          id: byteify(key.id, "hex"),
          type: "public-key",
          transports: ["usb", "nfc", "ble", "internal"],
        })),
        timeout: 60 * 1000,
      },
    })
    .catch(() => {
      queryingKey = false;
      return Promise.reject(null);
    })
    .then((credential) => {
      queryingKey = false;
      signing = true;
      return os.api("signin", {
        username,
        password,
        signature: hexify(credential.response.signature),
        authenticatorData: hexify(credential.response.authenticatorData),
        clientDataJSON: hexify(credential.response.clientDataJSON),
        credentialId: credential.id,
        challengeId: challengeData.challengeId,
        "hcaptcha-response": hCaptchaResponse,
        "g-recaptcha-response": reCaptchaResponse,
      });
    })
    .then((res) => {
      emit("login", { ...res, instance: instanceUrl });
      return onLogin({ ...res, instance: instanceUrl });
    })
    .catch((err) => {
      if (err === null) return;
      os.alert({
        type: "error",
        text: i18n.ts.signinFailed,
      });
      signing = false;
    });
}

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
