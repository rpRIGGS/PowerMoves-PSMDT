import type { PlayerData } from "@/interfaces/IPlayerData";
import { fetchNui } from "@/utils/fetchNui";
import { debugError } from "@/utils/debug";
import { TIMING } from "@/constants/index";
import { NUI_EVENTS } from "@/constants/nuiEvents";
import type { AuthUpdateData, InterfaceId, JobType } from "@/interfaces/IUser";
import { isEnvBrowser } from "@/utils/misc";
import { ALL_PERMISSION_KEYS } from "@/constants/management";

export interface PlayerInfo {
	rank: string;
	firstName: string;
	lastName: string;
	id: string;
	department: string;
}

export const MOCK_AUTH_DATA: AuthUpdateData = {
	authorized: true,
	playerData: {
		citizenid: "ABC12345",
		job: {
			name: "police",
			label: "Law Enforcement",
			grade: { name: "Officer", level: 1 },
			onduty: true,
			isboss: false,
		},
		charinfo: { firstname: "Mus", lastname: "Tashe" },
		metadata: { callsign: "69-420" },
	},
	isLEO: true,
	onDuty: true,
	permissions: ALL_PERMISSION_KEYS.filter(permission => !permission.startsWith('tab_hidden_')),
	isBoss: true,
	jobType: "leo",
	interfaceId: "sadle",
	allowedInterfaces: ["sadle"],
};

const DENIED_AUTH_DATA: AuthUpdateData = {
	authorized: false, eligible: false, isCivilian: false, onDuty: false,
	jobType: 'civilian', permissions: [], allowedInterfaces: [], isBoss: false,
};

/** Creates the authentication service */
export function createAuthService() {
	let isAuthorized = $state(false);
	let isCheckingAuth = $state(true);
	let authError = $state("");
	let playerData = $state<PlayerData | null>(null);
	let isLEO = $state(false);
	let onDuty = $state(false);
	let showLoadingScreen = $state(false);
	let showInterface = $state(false);
	let permissions = $state<string[]>([]);
	let isBoss = $state(false);
	let jobType = $state<JobType>("leo");
	let isCivilian = $state(false);
	let isLoadingPermissions = $state(false);
	let interfaceId = $state<InterfaceId | undefined>();
	let allowedInterfaces = $state<InterfaceId[]>([]);
	let agency = $state("");
	let jurisdiction = $state("");
	let role = $state("");
	let isSwitchingInterface = $state(false);
	let authRevision = 0;

	const playerInfo = $derived((): PlayerInfo => {
		if (!playerData) {
			return {
				rank: "Loading...",
				firstName: "",
				lastName: "",
				id: "",
				department: "",
			};
		}

		return {
			rank: playerData.job?.grade?.name || "Unknown",
			firstName: playerData.charinfo?.firstname || "",
			lastName: playerData.charinfo?.lastname || "",
			id: playerData.metadata?.callsign || playerData.citizenid || "",
			department: playerData.job?.label || "",
		};
	});

	function getAuthErrorMessage(authorized: boolean, isLEO: boolean): string {
		if (!authorized && isLEO) {
			return "You must be on duty to access the MDT system.";
		}
		if (!isLEO) {
			return "Access Denied: Authorized Personnel Only";
		}
		return "";
	}

	function processAuthData(data: AuthUpdateData): void {
		if (!data.playerData && !playerData) {
			isAuthorized = false;
			authError = "Failed to load player data.";
			return;
		}

		// Update player data
		playerData = data.playerData ?? playerData;
		isLEO = data.isLEO ?? (data.eligible === true && !data.isCivilian);
		onDuty = data.onDuty ?? playerData?.job?.onduty ?? false;
		isAuthorized = data.authorized || false;
		permissions = data.permissions || [];
		isBoss = data.isBoss || false;
		jobType = data.jobType || "leo";
		isCivilian = data.isCivilian || false;
		interfaceId = data.interfaceId;
		allowedInterfaces = data.allowedInterfaces || (interfaceId ? [interfaceId] : []);
		agency = data.agency || playerData?.job?.name || "";
		jurisdiction = data.jurisdiction || "";
		role = data.role || "";

		// Civilians are always authorized for their limited view
		if (isCivilian) {
			isAuthorized = true;
			onDuty = true;
		}

		// Set appropriate error message
		if (!isCivilian) {
			authError = getAuthErrorMessage(
				data.authorized || false,
				isLEO || data.authorized || false,
			);
		} else {
			authError = "";
		}
	}

	/** Updates authentication state from NUI event data */
	function updateAuthState(data: AuthUpdateData): void {
		authRevision++;
		processAuthData(data);
		isCheckingAuth = false;
		handleAuthComplete();
	}

	/** Performs initial authentication check with server */
	async function checkAuth(): Promise<void> {
		const revision = ++authRevision;
		try {
			isCheckingAuth = true;
			const response: AuthUpdateData = await fetchNui(
				NUI_EVENTS.AUTH.CHECK_AUTH,
				{},
				isEnvBrowser() ? MOCK_AUTH_DATA : DENIED_AUTH_DATA,
			);
			if (revision === authRevision) processAuthData(response);
		} catch (error) {
			if (revision !== authRevision) return;
			debugError("Auth check failed:", error);
			authError = "Failed to verify authorization.";
			isAuthorized = false;
		} finally {
			if (revision === authRevision) {
				isCheckingAuth = false;
				handleAuthComplete();
			}
		}
	}

	let loadingTimeout: ReturnType<typeof setTimeout> | null = $state(null);

	function determineUIState(
		authorized: boolean,
		isLEO: boolean,
		onDuty: boolean,
	): {
		showInterface: boolean;
		showLoadingScreen: boolean;
	} {
		// The server applies duty policy, including DOJ and configured exceptions.
		if (authorized) {
			return { showInterface: true, showLoadingScreen: false };
		}

		// LEO but off duty - show temporary loading screen
		if (isLEO && !onDuty) {
			return { showInterface: false, showLoadingScreen: true };
		}

		// Not LEO - hide everything
		return { showInterface: false, showLoadingScreen: false };
	}

	function clearLoadingTimeout(): void {
		if (loadingTimeout) {
			clearTimeout(loadingTimeout);
			loadingTimeout = null;
		}
	}

	/** Handles auth completion and updates UI state */
	function handleAuthComplete(): void {
		// Clear any existing timeout
		clearLoadingTimeout();

		// Determine and set UI state
		const uiState = determineUIState(isAuthorized, isLEO, onDuty);
		showInterface = uiState.showInterface;
		showLoadingScreen = uiState.showLoadingScreen;

		// If showing loading screen, set timeout to hide it
		if (showLoadingScreen) {
			loadingTimeout = setTimeout(() => {
				showLoadingScreen = false;
				loadingTimeout = null;
			}, TIMING.offDutyLoadingDuration);
		}

		if (
			isAuthorized &&
			!isLoadingPermissions &&
			!isCivilian &&
			jobType !== 'gov' &&
			permissions.length === 0
		) {
			loadPermissions();
		}
	}

	/** Fetches the current player's permissions from the server */
	async function loadPermissions(force = false): Promise<void> {
		if (isLoadingPermissions || (!force && permissions.length > 0)) return;
		const revision = authRevision;

		try {
			isLoadingPermissions = true;
			const response = await fetchNui<AuthUpdateData>(
				NUI_EVENTS.AUTH.GET_INTERFACE_ACCESS,
				{},
				isEnvBrowser() ? MOCK_AUTH_DATA : DENIED_AUTH_DATA,
			);
			if (revision === authRevision) {
				processAuthData(response);
				handleAuthComplete();
			}
		} catch (error) {
			if (revision !== authRevision) return;
			debugError("Failed to load permissions:", error);
			permissions = [];
			isBoss = false;
		} finally {
			isLoadingPermissions = false;
		}
	}

	async function selectInterface(nextInterface: InterfaceId): Promise<void> {
		if (isSwitchingInterface || nextInterface === interfaceId) return;
		if (!allowedInterfaces.includes(nextInterface)) throw new Error("Interface access denied.");
		const revision = ++authRevision;
		isSwitchingInterface = true;
		try {
			const response = await fetchNui<AuthUpdateData & { success?: boolean; message?: string; error?: string }>(
				NUI_EVENTS.AUTH.SET_INTERFACE, { interfaceId: nextInterface }, { ...DENIED_AUTH_DATA, success: false },
			);
			if (revision !== authRevision) return;
			if (response.success === false || !response.authorized || response.interfaceId !== nextInterface) {
				throw new Error(response.error || response.message || "Unable to switch interfaces.");
			}
			processAuthData(response);
			handleAuthComplete();
		} finally {
			isSwitchingInterface = false;
		}
	}

	/** Sends request to go on duty */
	async function goOnDuty(): Promise<void> {
		try {
			// Clear loading screen immediately when user takes action
			clearLoadingTimeout();
			showLoadingScreen = false;

			await fetchNui(NUI_EVENTS.AUTH.GO_ON_DUTY);
		} catch (error) {
			debugError("Failed to go on duty:", error);
			// Don't manipulate loading screen here - let auth updates handle UI state
		}
	}

	/** Signs user out of MDT system */
	function signOut(): void {
		try {
			clearLoadingTimeout();
			fetchNui(NUI_EVENTS.AUTH.SIGN_OUT);
		} catch (error) {
			debugError("Failed to sign out:", error);
		}
	}

	/** Closes the MDT user interface */
	function closeUI(): void {
		clearLoadingTimeout();
		fetchNui(NUI_EVENTS.NAVIGATION.CLOSE_UI);
	}

	/** Check if the current user has a specific permission */
	function hasPermission(perm: string): boolean {
		return permissions.includes(perm);
	}

	/** Check if the current user has any of the given permissions */
	function hasAnyPermission(...perms: string[]): boolean {
		return perms.some((p) => permissions.includes(p));
	}

	/** Check permission without boss override (used for tab_hidden_* checks) */
	function hasRawPermission(perm: string): boolean {
		return permissions.includes(perm);
	}

	return {
		// State
		get isAuthorized() {
			return isAuthorized;
		},
		get isCheckingAuth() {
			return isCheckingAuth;
		},
		get authError() {
			return authError;
		},
		get playerData() {
			return playerData;
		},
		get isLEO() {
			return isLEO;
		},
		get onDuty() {
			return onDuty;
		},
		get showLoadingScreen() {
			return showLoadingScreen;
		},
		get showInterface() {
			return showInterface;
		},
		get playerInfo() {
			return playerInfo;
		},
		get isLoadingPermissions() {
			return isLoadingPermissions;
		},
		get permissions() {
			return permissions;
		},
		get isBoss() {
			return isBoss;
		},
		get jobType() {
			return jobType;
		},
		get isCivilian() {
			return isCivilian;
		},
		get interfaceId() { return interfaceId; },
		get allowedInterfaces() { return allowedInterfaces; },
		get agency() { return agency; },
		get jurisdiction() { return jurisdiction; },
		get role() { return role; },
		get isSwitchingInterface() { return isSwitchingInterface; },

		// Actions
		/** Updates authentication state from NUI event data */
		updateAuthState,

		/** Performs initial authentication check with server */
		checkAuth,

		/** Sends request to go on duty */
		goOnDuty,

		/** Signs user out of MDT system */
		signOut,

		/** Closes the MDT user interface */
		closeUI,

		/** Check if the current user has a specific permission */
		hasPermission,

		/** Check if the current user has any of the given permissions */
		hasAnyPermission,

		hasRawPermission,
		selectInterface,
		handleAuthComplete,
	};
}

export interface AuthService {
	// State getters
	readonly isAuthorized: boolean;
	readonly isCheckingAuth: boolean;
	readonly authError: string;
	readonly playerData: PlayerData | null;
	readonly isLEO: boolean;
	readonly onDuty: boolean;
	readonly showLoadingScreen: boolean;
	readonly showInterface: boolean;
	readonly playerInfo: () => PlayerInfo;
	readonly isLoadingPermissions: boolean;
	readonly permissions: string[];
	readonly isBoss: boolean;
	readonly jobType: JobType;
	readonly isCivilian: boolean;
	readonly interfaceId: InterfaceId | undefined;
	readonly allowedInterfaces: InterfaceId[];
	readonly agency: string;
	readonly jurisdiction: string;
	readonly role: string;
	readonly isSwitchingInterface: boolean;

	// Actions
	updateAuthState: (data: AuthUpdateData) => void;
	checkAuth: () => Promise<void>;
	handleAuthComplete: () => void;
	goOnDuty: () => Promise<void>;
	signOut: () => void;
	closeUI: () => void;
	hasPermission: (perm: string) => boolean;
	hasAnyPermission: (...perms: string[]) => boolean;
	hasRawPermission: (perm: string) => boolean;
	selectInterface: (interfaceId: InterfaceId) => Promise<void>;
}
