import { CapacitorHttp } from "@capacitor/core";

function join(...paths: string[]) {
  return paths.join("/");
}
async function ky(url: string, options: any) {
  const response = await fetch(url, options);
  if (!response.ok) {
    throw new Error(`HTTP error: ${response.statusText}`);
  }
  return response;
}

/**
 * parametor of MiAuth url
 */
export interface UrlParam {
  name: string;
  callback?: string;
  permission: Array<string>;
}

/**
 * thow when incorrect format url parameter hand over MiAuth class
 */
class UrlParameterError extends Error {
  constructor() {
    // TODO: ここに気の利いたエラーを入れる
    super("UrlParameterError");
  }
}

class AuthenticationError extends Error {
  constructor() {
    // TODO: ここに気の利いたエラーを入れる
    super("AuthenticationError");
  }
}

export class MiAuth {
  /**
   * MiAuth constructor
   *
   * origin:
   *   your on the instance url
   *
   * param:
   *   url parameter. see UrlParam
   */

  private origin: string;
  private param: UrlParam;
  private session: string;

  constructor(origin: string, param: UrlParam, session: string) {
    this.origin = origin;
    this.param = param;
    this.session = session;
  }

  /**
   * return miauth authentication url
   */
  public authUrl(): string {
    const param = this.buildParam(this.param);
    const requestUrl = new URL(join("miauth", this.session), this.origin);

    requestUrl.search = param;
    return requestUrl.toString();
  }

  /**
   * return misskey api token
   * when failed authentication, throw AuthenticationError
   */
  public async getToken(): Promise<string> {
    const url = new URL(
      join("api", "miauth", this.session, "check"),
      this.origin
    );
    const data: Record<string, unknown> = await CapacitorHttp.request(
      {
        method: "POST",
        url: url.href
      }).then(res => res.data)
    const token = String(data.token);
    if (typeof data.token === "undefined") {
      throw new AuthenticationError();
    }
    return token;
  }

  /**
   * build for parameter of miauth authentication url
   * when you incorrect parameter, thow UrlParametorError,
   * but, when callback parameter incorrect do not throw that error
   */
  private buildParam(param: UrlParam): string {
    const urlParam: Record<string, string> = {
      name: param.name,
      callback: param.callback as string,
      permission: param.permission.join(","),
    };

    const convertdParam = new URLSearchParams();

    Object.keys(urlParam).forEach((key) => {
      convertdParam.set(key, String(urlParam[key]));
      if (key != "callback") {
        if (typeof urlParam[key] === "undefined") {
          throw UrlParameterError;
        }
      } else {
        if (typeof urlParam[key] === "undefined") {
          convertdParam.delete("callback");
        }
      }
    });
    return convertdParam.toString();
  }
}

/**
 *  this is MiAuth constructor light wrapper
 */
export function quickAuth(origin: string, param: UrlParam): MiAuth {
  const session = crypto.randomUUID();
  return new MiAuth(origin, param, session);
}

export const Permissions = [
  "read:account",
  "write:account",
  "write:notes",
  "read:blocks",
  "write:blocks",
  "read:drive",
  "write:drive",
  "read:favorites",
  "write:favorites",
  "read:following",
  "write:following",
  "read:messaging",
  "write:messaging",
  "read:mutes",
  "write:mutes",
  "read:notifications",
  "write:notifications",
  "read:reactions",
  "write:reactions",
  "write:votes",
  "read:pages",
  "write:pages",
  "read:page-likes",
  "write:page-likes",
  "read:user-groups",
  "write:user-groups",
  "read:channels",
  "write:channels",
];
