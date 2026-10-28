import { fetchNui } from "../utils/fetchNui";
import { NUI_EVENTS } from "../constants/nuiEvents";
import type { GovernmentDepartment, GovernmentEmployee, GovernmentRosterResponse, GovernmentHireCandidate, GovernmentEmploymentResult } from "../interfaces/IGovernment";

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
	let canManagePersonnel = $state(false);
	let isSaving = $state(false);
	let isFindingCandidate = $state(false);
	let hireCandidate = $state<GovernmentHireCandidate | null>(null);
	let actionError = $state("");
	let actionMessage = $state("");
	let revision = 0;
	let actionRevision = 0;
	let candidateRevision = 0;

	function clearData() {
		roster = [];
		departments = [];
		selectedDepartment = "";
		hasOversight = false;
		canManagePersonnel = false;
	}

	function clearHireCandidate() {
		candidateRevision++;
		hireCandidate = null;
		isFindingCandidate = false;
	}

	function clearActionStatus() {
		actionError = "";
		actionMessage = "";
	}

	function reset() {
		revision++;
		actionRevision++;
		clearHireCandidate();
		clearActionStatus();
		clearData();
		isSaving = false;
		isLoading = false;
		error = "";
	}

	async function loadRoster(department?: string): Promise<void> {
		const request = ++revision;
		clearHireCandidate();
		canManagePersonnel = false;
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
			canManagePersonnel = response.canManagePersonnel === true;
		} catch (failure) {
			if (request !== revision) return;
			clearData();
			error = failure instanceof Error ? failure.message : "Unable to load government personnel.";
		} finally {
			if (request === revision) isLoading = false;
		}
	}

	function canAct(): boolean {
		if (isSaving || isLoading) return false;
		if (!canManagePersonnel || !selectedDepartment) {
			actionError = "You cannot manage personnel in this department.";
			return false;
		}
		return true;
	}

	function validGrade(grade: number): boolean {
		return Number.isInteger(grade) && departments.find(item => item.job === selectedDepartment)?.grades.some(item => item.grade === grade) === true;
	}

	async function findHireCandidate(serverId: number): Promise<boolean> {
		if (!canAct()) return false;
		clearHireCandidate();
		clearActionStatus();
		if (!Number.isSafeInteger(serverId) || serverId <= 0) {
			actionError = "Enter a valid online player server ID.";
			return false;
		}
		const request = ++candidateRevision;
		const scope = revision;
		isFindingCandidate = true;
		try {
			const response = await fetchNui<GovernmentEmploymentResult & { candidate?: GovernmentHireCandidate }>(
				NUI_EVENTS.ROSTER.GET_GOVERNMENT_HIRE_CANDIDATE,
				{ serverId, department: selectedDepartment },
				{ success: false, error: "Unable to find an eligible player. Please try again." },
			);
			if (request !== candidateRevision || scope !== revision) return false;
			if (!response?.success || !response.candidate?.citizenid || response.candidate.serverId !== serverId) {
				throw new Error(response?.error || "No eligible online player was found.");
			}
			hireCandidate = response.candidate;
			return true;
		} catch (failure) {
			if (request === candidateRevision && scope === revision) actionError = failure instanceof Error ? failure.message : "Unable to find an eligible player.";
			return false;
		} finally {
			if (request === candidateRevision) isFindingCandidate = false;
		}
	}

	async function employmentAction(event: typeof NUI_EVENTS.ROSTER.HIRE_GOVERNMENT_EMPLOYEE | typeof NUI_EVENTS.ROSTER.SET_GOVERNMENT_EMPLOYEE_GRADE | typeof NUI_EVENTS.ROSTER.TERMINATE_GOVERNMENT_EMPLOYEE, payload: Record<string, string | number>): Promise<boolean> {
		if (!canAct()) return false;
		const request = ++actionRevision;
		const scope = revision;
		const department = selectedDepartment;
		clearActionStatus();
		isSaving = true;
		try {
			const result = await fetchNui<GovernmentEmploymentResult>(event, { ...payload, department }, { success: false, error: "Personnel change could not be confirmed. Refresh the roster before trying again." });
			if (request !== actionRevision || scope !== revision) return false;
			if (!result?.success) throw new Error(result?.error || "The personnel change was denied.");
			await loadRoster(department);
			if (request !== actionRevision) return false;
			actionMessage = result.message || "Personnel updated.";
			return true;
		} catch (failure) {
			if (request === actionRevision && scope === revision) actionError = failure instanceof Error ? failure.message : "Unable to update personnel.";
			return false;
		} finally {
			if (request === actionRevision) isSaving = false;
		}
	}

	async function hireEmployee(grade: number): Promise<boolean> {
		if (!canAct()) return false;
		if (!hireCandidate || !validGrade(grade)) {
			actionError = "Select an eligible player and a valid position.";
			return false;
		}
		return employmentAction(NUI_EVENTS.ROSTER.HIRE_GOVERNMENT_EMPLOYEE, { citizenid: hireCandidate.citizenid, serverId: hireCandidate.serverId, grade });
	}

	async function changeGrade(citizenid: string, grade: number): Promise<boolean> {
		if (!canAct()) return false;
		if (!validGrade(grade) || !roster.some(employee => employee.citizenid === citizenid && employee.department === selectedDepartment)) {
			actionError = "Select an employee in this department and a valid position.";
			return false;
		}
		return employmentAction(NUI_EVENTS.ROSTER.SET_GOVERNMENT_EMPLOYEE_GRADE, { citizenid, grade });
	}

	async function terminateEmployee(citizenid: string): Promise<boolean> {
		if (!canAct()) return false;
		if (!roster.some(employee => employee.citizenid === citizenid && employee.department === selectedDepartment)) {
			actionError = "Select an employee in this department.";
			return false;
		}
		return employmentAction(NUI_EVENTS.ROSTER.TERMINATE_GOVERNMENT_EMPLOYEE, { citizenid });
	}

	return {
		loadRoster, reset, clearHireCandidate, clearActionStatus,
		findHireCandidate, hireEmployee, changeGrade, terminateEmployee,
		get roster() { return roster; },
		get departments() { return departments; },
		get selectedDepartment() { return selectedDepartment; },
		get hasOversight() { return hasOversight; },
		get isLoading() { return isLoading; },
		get error() { return error; },
		get canManagePersonnel() { return canManagePersonnel; },
		get isSaving() { return isSaving; },
		get isFindingCandidate() { return isFindingCandidate; },
		get hireCandidate() { return hireCandidate; },
		get actionError() { return actionError; },
		get actionMessage() { return actionMessage; },
	};
}
