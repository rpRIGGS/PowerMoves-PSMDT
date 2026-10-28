import type { PlayerData } from "./IPlayerData";

export type JobType = 'leo' | 'ems' | 'doj' | 'gov' | 'civilian';
export type InterfaceId = 'sadle' | 'sadoj' | 'safr' | 'sams' | 'sagov';

export interface AuthUpdateData {
	playerData?: PlayerData;
	isLEO?: boolean;
	onDuty?: boolean;
	authorized?: boolean;
	permissions?: string[];
	isBoss?: boolean;
	jobType?: JobType;
	isCivilian?: boolean;
	eligible?: boolean;
	interfaceId?: InterfaceId;
	allowedInterfaces?: InterfaceId[];
	agency?: string;
	jurisdiction?: string;
	role?: string;
}
