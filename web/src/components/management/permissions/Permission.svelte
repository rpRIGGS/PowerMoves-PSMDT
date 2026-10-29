<script lang="ts">
	import { PERMISSION_CATEGORIES } from "@/constants/management";
	import { onMount } from "svelte";

	let permissions = PERMISSION_CATEGORIES.flatMap(category => category.permissions.map(permission => permission.label));
</script>

<div class="permissions">
	{#each permissions as permission}
		<div class="permission">{permission}</div>
	{/each}
</div>
