export interface GovernmentEmployee {
	citizenid: string;
	firstName: string;
	lastName: string;
	rank: string;
	grade?: number;
	department: string;
	departmentLabel: string;
	jurisdiction: string;
}

export interface GovernmentDepartment {
	job: string;
	label: string;
	jurisdiction: string;
	jurisdictionLabel: string;
	parentJurisdiction?: string;
	grades: { grade: number; name: string }[];
}

export interface GovernmentRosterResponse {
	success: boolean;
	error?: string;
	roster: GovernmentEmployee[];
	departments: GovernmentDepartment[];
	selectedDepartment?: string;
	hasOversight?: boolean;
	canManagePersonnel?: false;
}
