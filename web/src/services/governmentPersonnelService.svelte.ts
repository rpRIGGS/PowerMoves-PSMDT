import { fetchNui } from "../utils/fetchNui";
import { NUI_EVENTS } from "../constants/nuiEvents";
import type { GovernmentDepartment, GovernmentEmployee, GovernmentRosterResponse } from "../interfaces/IGovernment";

// Empty Lua tables may arrive as either [] or {} through the NUI bridge.
function arrayFromLua<T>(value: unknown): T[] | null {
	if (Array.isArray(value)) return value;
	if (value && typeof value === "object" && Object.keys(value).length === 0) return [];
	return null;
}

export function createGovernmentPersonnelService() {
	let roster = $state<GovernmentEmployee[]>([]);
	let departments = $state<GovernmentDepartment[]>([]);
	let selectedDepartment = $state("");
	let hasOversight = $state(false);
	let isLoading = $state(false);
	let error = $state("");
	let revision = 0;

	function clearData() {
		roster = [];
		departments = [];
		selectedDepartment = "";
		hasOversight = false;
	}

	function reset() {
		revision++;
		clearData();
		isLoading = false;
		error = "";
	}

	async function loadRoster(department?: string): Promise<void> {
		const request = ++revision;
		isLoading = true;
		error = "";
		roster = [];
		try {
			const response = await fetchNui<GovernmentRosterResponse>(
				NUI_EVENTS.ROSTER.GET_GOVERNMENT_ROSTER,
				department ? { department } : {},
				{ success: false, error: "Government roster unavailable. Please try again.", roster: [], departments: [] },
			);
			if (request !== revision) return;
			if (!response?.success) throw new Error(response?.error || "Unable to load government personnel.");
			const employees = arrayFromLua<GovernmentEmployee>(response.roster);
			const authorizedDepartments = arrayFromLua<GovernmentDepartment>(response.departments);
			if (!employees || !authorizedDepartments ||
				!authorizedDepartments.some(item => item.job === response.selectedDepartment) ||
				employees.some(item => item.department !== response.selectedDepartment)) {
				throw new Error("The government roster response was incomplete. Please refresh.");
			}
			roster = employees;
			departments = authorizedDepartments;
			selectedDepartment = response.selectedDepartment!;
			hasOversight = response.hasOversight === true;
		} catch (failure) {
			if (request !== revision) return;
			clearData();
			error = failure instanceof Error ? failure.message : "Unable to load government personnel.";
		} finally {
			if (request === revision) isLoading = false;
		}
	}

	return {
		loadRoster, reset,
		get roster() { return roster; },
		get departments() { return departments; },
		get selectedDepartment() { return selectedDepartment; },
		get hasOversight() { return hasOversight; },
		get isLoading() { return isLoading; },
		get error() { return error; },
	};
}
