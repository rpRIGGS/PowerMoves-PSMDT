<script lang="ts">
	import { onMount } from "svelte";
	import { fetchNui } from "../utils/fetchNui";
	import { NUI_EVENTS } from "../constants/nuiEvents";
	import {
		DEFAULT_TIME,
		DEFAULT_DATE,
		TIMING,
		INTERFACE_INFO,
		getInterfaceInfo,
	} from "../constants";
	import { formatTime, formatDate } from "../utils/datetime";

	import type { AuthService } from "../services/authService.svelte";
	import type { InterfaceId } from "../interfaces/IUser";
	import { globalNotifications } from "../services/notificationService.svelte";

	interface Props {
		authService: AuthService;
		onOpacityStyleChange: (opacityStyle: string) => void;
	}

	let { authService, onOpacityStyleChange }: Props = $props();
	let info = $derived(getInterfaceInfo(authService.interfaceId, authService.jobType));

	let currentTime = $state(DEFAULT_TIME);
	let currentDate = $state(DEFAULT_DATE);
	let opacityTimeout: ReturnType<typeof setTimeout> | null = $state(null);
	let documentOpacity = $state(1);

	async function switchInterface(event: Event) {
		try {
			await authService.selectInterface((event.target as HTMLSelectElement).value as InterfaceId);
		} catch (error) {
			(event.target as HTMLSelectElement).value = authService.interfaceId || "";
			globalNotifications.error(error instanceof Error ? error.message : "Unable to switch interfaces.");
		}
	}

	/**
	 * Reactive statement for the opacity style string.
	 */
	const opacityStyle = $derived(`opacity: ${documentOpacity}`);

	/**
	 * Watch for opacity style changes and notify parent.
	 */
	$effect(() => {
		onOpacityStyleChange(opacityStyle);
	});

	function handleTopBarEnter() {
		if (opacityTimeout) {
			clearTimeout(opacityTimeout);
			opacityTimeout = null;
		}
		documentOpacity = 0.25;
	}

	function handleTopBarLeave() {
		if (opacityTimeout) {
			clearTimeout(opacityTimeout);
		}

		opacityTimeout = setTimeout(() => {
			documentOpacity = 1;
			opacityTimeout = null;
		}, TIMING.topBarOpacityDelay);
	}

	/**
	 * Initializes the time update interval and cleans up on component destruction.
	 */
	onMount(() => {
		const timeInterval = setInterval(() => {
			const now = new Date();
			currentTime = formatTime(now);
			currentDate = formatDate(now);
		}, TIMING.timeUpdateInterval);

		return () => {
			clearInterval(timeInterval);
			if (opacityTimeout) {
				clearTimeout(opacityTimeout);
			}
		};
	});
</script>

<div
	class="top-bar"
	role="region"
	onmouseenter={handleTopBarEnter}
	onmouseleave={handleTopBarLeave}
>
	<div class="user-info">
		<span class="interface-name">{info.name}</span>
		{#if authService.isAuthorized}
			{authService.playerInfo().rank}
			{authService.playerInfo().firstName}
			{authService.playerInfo().lastName} | {authService.playerInfo().id} |
			{authService.playerInfo().department}
		{:else}
			{info.title} - {info.subtitle}
		{/if}
	</div>
	{#if authService.isAuthorized && authService.allowedInterfaces.length > 1}
		<select class="interface-switch" aria-label="Active interface" value={authService.interfaceId} disabled={authService.isSwitchingInterface} onchange={switchInterface}>
			{#each authService.allowedInterfaces as interfaceId}
				<option value={interfaceId}>{INTERFACE_INFO[interfaceId].name}</option>
			{/each}
		</select>
	{/if}
	<div class="time-info">
		{currentTime} | {currentDate}
	</div>
</div>

<style>
	.top-bar {
		background: rgba(13, 13, 13, 0.7);
		min-height: 55px;
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 0 20px;
		color: var(--primary-text);
		font-size: 14px;
		font-weight: 500;
		border-bottom: 1px solid var(--border-primary);
		z-index: 10;
		position: relative;
		cursor: default;
	}

	:global([data-job-type="ems"]) .top-bar {
		background: rgba(18, 10, 10, 0.8);
		border-bottom-color: rgba(220, 50, 50, 0.12);
	}

	:global([data-job-type="doj"]) .top-bar {
		background: rgba(8, 12, 20, 0.8);
		border-bottom-color: rgba(180, 150, 60, 0.12);
	}

	.user-info,
	.time-info {
		color: var(--primary-text);
	}

	.interface-name { margin-right: 14px; font-weight: 700; }
	.interface-switch { margin: 0 16px; padding: 6px 9px; border: 1px solid var(--border-primary); border-radius: 4px; background: #1a1d23; color: var(--primary-text); font: inherit; }
</style>
