<script lang="ts">
    import {
        beforeNavigate,
        goto,
        invalidateAll,
    } from "$app/navigation";

    import { page } from "$app/state";
    import { env } from "$env/dynamic/public";
    import Toast from "$lib/components/base/toast.svelte";
    import Footer from "$lib/components/footer.svelte";
    import NavBar from "$lib/components/nav_bar.svelte";
    import PageLoadingBar from "$lib/components/page_loading_bar.svelte";
    import UploadDialog from "$lib/components/settings/upload_dialog.svelte";
    import { getPb } from "$lib/pocketbase";
    import { currentUser } from "$lib/stores/user_store";
    import { load_plugin_data_once } from "$lib/stores/plugin_store";
    import { isRouteProtected } from "$lib/util/authorization_util";
    import { onMount, type Snippet } from "svelte";
    import { slide } from "svelte/transition";
    import "../css/app.css";
    import "../css/components.css";
    import "../css/theme.css";
    import type { LayoutData } from "./$types";

    interface Props {
        data: LayoutData;
        children?: Snippet;
    }

    let { data, children }: Props = $props();

    beforeNavigate((n) => {
        if (!$currentUser && isRouteProtected(n.to?.url)) {
            n.cancel();
            goto("/login?r=" + n.to?.url?.pathname);
        }
    });

    onMount(() => {
        if (page.data.origin != location.origin) {
            showWarning = true;
        }
        if (data.user) {
            load_plugin_data_once();
        }
    });

    type AuthIdentity = string | null;

    interface ClientAuthSession {
        identity: AuthIdentity;
        key: string;
    }

    let lastRequestedAuthSessionKey: string | undefined;
    let queuedAuthSession: ClientAuthSession | undefined;
    let authRefreshInFlight: Promise<void> | undefined;

    function clientAuthSession(): ClientAuthSession | undefined {
        if ($currentUser === undefined) {
            return undefined;
        }

        const identity = $currentUser?.id ?? null;
        return {
            identity,
            key: `${identity ?? ""}\u0000${getPb().authStore.token}`,
        };
    }

    function serverAuthIdentity(): AuthIdentity {
        return data.user?.id ?? null;
    }

    async function runAuthRefreshQueue() {
        while (queuedAuthSession !== undefined) {
            const expectedClientSession = queuedAuthSession;
            queuedAuthSession = undefined;

            try {
                await invalidateAll();
            } catch {
                if (
                    clientAuthSession()?.key === expectedClientSession.key &&
                    lastRequestedAuthSessionKey === expectedClientSession.key
                ) {
                    lastRequestedAuthSessionKey = undefined;
                }
                continue;
            }

            const currentClientSession = clientAuthSession();
            const pb = getPb();
            if (currentClientSession?.key === expectedClientSession.key) {
                pb.authStore.loadFromCookie(document.cookie);
            } else if (currentClientSession) {
                document.cookie = pb.authStore.exportToCookie({
                    httpOnly: false,
                    secure: location.protocol === "https:",
                    sameSite: "Lax",
                });
            }
        }
    }

    function requestAuthRefresh(session: ClientAuthSession): Promise<void> {
        queuedAuthSession = session;
        if (!authRefreshInFlight) {
            authRefreshInFlight = runAuthRefreshQueue().finally(() => {
                authRefreshInFlight = undefined;
                if (queuedAuthSession !== undefined) {
                    void requestAuthRefresh(queuedAuthSession);
                }
            });
        }
        return authRefreshInFlight;
    }

    $effect(() => {
        const clientSession = clientAuthSession();
        if (clientSession === undefined) {
            return;
        }

        if (clientSession.identity === serverAuthIdentity()) {
            lastRequestedAuthSessionKey = undefined;
            return;
        }

        if (clientSession.key !== lastRequestedAuthSessionKey) {
            lastRequestedAuthSessionKey = clientSession.key;
            void requestAuthRefresh(clientSession);
        }
    });

    async function handlePageShow(event: PageTransitionEvent) {
        if (!event.persisted) {
            return;
        }

        const pb = getPb();
        pb.authStore.loadFromCookie(document.cookie);

        const restoredSession = clientAuthSession();
        if (!restoredSession) {
            return;
        }
        lastRequestedAuthSessionKey = restoredSession.key;
        await requestAuthRefresh(restoredSession);
    }

    let hideDemoHint = $state(false);
    let showWarning = $state(false);
</script>

<svelte:window onpageshow={handlePageShow} />

{#if env.PUBLIC_IS_DEMO === "true" && !hideDemoHint}
    <div
        class="flex items-center justify-between bg-amber-200 text-center p-4 text-sm text-black"
        out:slide
    >
        <div></div>
        <span
            >This is a demo instance. Do not store any relevant data here. You
            can use the user 'demo' and password 'password' to login.
        </span>
        <button
            aria-label="Close"
            class="btn-icon self-end"
            onclick={() => (hideDemoHint = true)}
            ><i class="fa fa-close"></i></button
        >
    </div>
{/if}

{#if showWarning && !page.url.pathname.startsWith("/live/")}
    <div
        class="flex items-center justify-between bg-red-200 text-center p-4 text-sm text-black"
        out:slide
    >
        <div></div>
        <p>
            You are accessing Live Ride from <span class="font-mono bg-gray-100"
                >{location.origin}</span
            >
            but your ORIGIN environment variable is set to
            <span class="font-mono bg-gray-100">{page.data.origin}</span>. This
            may cause errors.
        </p>
        <button
            aria-label="Close"
            class="btn-icon self-end"
            onclick={() => (showWarning = false)}
            ><i class="fa fa-close"></i></button
        >
    </div>
{/if}

{#if page.url.pathname.startsWith("/live/")}
    {@render children?.()}
{:else}
    <NavBar user={data.user}></NavBar>
    <PageLoadingBar class="text-content"></PageLoadingBar>
    <Toast></Toast>
    <UploadDialog></UploadDialog>
    {@render children?.()}
    <Footer></Footer>
{/if}
