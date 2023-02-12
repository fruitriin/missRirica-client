import autobind from 'autobind-decorator';
import { markRaw, ref, Ref, unref } from 'vue';
import { collectPageVars } from '../collect-page-vars';
import { initHpmlLib, initAiLib } from './lib';
import { Expr, isLiteralValue, Variable } from './expr';
import { PageVar, envVarsDef, Fn, HpmlScope, HpmlError } from '.';
import { version } from '@/config';
import * as os from '@/os';

/**
 * Hpml evaluator
 */
export class Hpml {
	private variables: Variable[];
	private pageVars: PageVar[];
	private envVars: Record<keyof typeof envVarsDef, any>;
	public pageVarUpdatedCallback?: values.VFn;
	public canvases: Record<string, HTMLCanvasElement> = {};
	public vars: Ref<Record<string, any>> = ref({});
	public page: Record<string, any>;

	private opts: {
		randomSeed: string; visitor?: any; url?: string;
	};

	constructor(page: Hpml['page'], opts: Hpml['opts']) {
		this.page = page;
		this.variables = this.page.variables;
		this.pageVars = collectPageVars(this.page.content);
		this.opts = opts;

		const date = new Date();

		this.envVars = {
			AI: 'kawaii',
			VERSION: version,
			URL: this.page ? `${opts.url}/@${this.page.user.username}/pages/${this.page.name}` : '',
			LOGIN: opts.visitor != null,
			NAME: opts.visitor ? opts.visitor.name || opts.visitor.username : '',
			USERNAME: opts.visitor ? opts.visitor.username : '',
			USERID: opts.visitor ? opts.visitor.id : '',
			NOTES_COUNT: opts.visitor ? opts.visitor.notesCount : 0,
			FOLLOWERS_COUNT: opts.visitor ? opts.visitor.followersCount : 0,
			FOLLOWING_COUNT: opts.visitor ? opts.visitor.followingCount : 0,
			IS_CAT: opts.visitor ? opts.visitor.isCat : false,
			SEED: opts.randomSeed ? opts.randomSeed : '',
			YMD: `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`,
			AISCRIPT_DISABLED: true,
			NULL: null,
		};

		this.eval();
	}

	@autobind
	public eval() {
		try {
			this.vars.value = this.evaluateVars();
		} catch (err) {
			//this.onError(e);
		}
	}

	@autobind
	public interpolate(str: string) {
		if (str == null) return null;
		return str.replace(/{(.+?)}/g, match => {
			const v = unref(this.vars)[match.slice(1, -1).trim()];
			return v == null ? 'NULL' : v.toString();
		});
	}

	@autobind
	public registerCanvas(id: string, canvas: any) {
		this.canvases[id] = canvas;
	}

	@autobind
	public updatePageVar(name: string, value: any) {
		const pageVar = this.pageVars.find(v => v.name === name);
		if (pageVar !== undefined) {
			pageVar.value = value;
		} else {
			throw new HpmlError(`No such page var '${name}'`);
		}
	}

	@autobind
	public updateRandomSeed(seed: string) {
		this.opts.randomSeed = seed;
		this.envVars.SEED = seed;
	}

	@autobind
	private _interpolateScope(str: string, scope: HpmlScope) {
		return str.replace(/{(.+?)}/g, match => {
			const v = scope.getState(match.slice(1, -1).trim());
			return v == null ? 'NULL' : v.toString();
		});
	}

	@autobind
	public evaluateVars(): Record<string, any> {
		const values: Record<string, any> = {};

		for (const [k, v] of Object.entries(this.envVars)) {
			values[k] = v;
		}

		for (const v of this.pageVars) {
			values[v.name] = v.value;
		}

		for (const v of this.variables) {
			values[v.name] = this.evaluate(v, new HpmlScope([values]));
		}

		return values;
	}

	@autobind
	private evaluate(expr: Expr, scope: HpmlScope): any {
		if (isLiteralValue(expr)) {
			if (expr.type === null) {
				return null;
			}

			if (expr.type === 'number') {
				return parseInt((expr.value as any), 10);
			}

			if (expr.type === 'text' || expr.type === 'multiLineText') {
				return this._interpolateScope(expr.value || '', scope);
			}

			if (expr.type === 'textList') {
				return this._interpolateScope(expr.value || '', scope).trim().split('\n');
			}

			if (expr.type === 'ref') {
				return scope.getState(expr.value);
			}

			// Define user function
			if (expr.type === 'fn') {
				return {
					slots: expr.value.slots.map(x => x.name),
					exec: (slotArg: Record<string, any>) => {
						return this.evaluate(expr.value.expression, scope.createChildScope(slotArg, expr.id));
					},
				} as Fn;
			}
			return;
		}

		// Call user function
		if (expr.type.startsWith('fn:')) {
			const fnName = expr.type.split(':')[1];
			const fn = scope.getState(fnName);
			const args = {} as Record<string, any>;
			for (let i = 0; i < fn.slots.length; i++) {
				const name = fn.slots[i];
				args[name] = this.evaluate(expr.args[i], scope);
			}
			return fn.exec(args);
		}

		if (expr.args === undefined) return null;

		const funcs = initHpmlLib(expr, scope, this.opts.randomSeed, this.opts.visitor);

		// Call function
		const fnName = expr.type;
		const fn = (funcs as any)[fnName];
		if (fn == null) {
			throw new HpmlError(`No such function '${fnName}'`);
		} else {
			return fn(...expr.args.map(x => this.evaluate(x, scope)));
		}
	}
}
