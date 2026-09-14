import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getCurrentCycle from '@salesforce/apex/StatementStatusController.getCurrentCycle';

const STATUS_CHANNEL = '/event/Statement_Ready__e';

/**
 * Presentation for each stored picklist value. 'Draft' means the statement exists but generation
 * hasn't started, which reads as Queued to anyone watching the page.
 */
const PRESENTATION = {
    Draft: { label: 'Queued', theme: 'queued', icon: 'utility:clock', busy: true },
    Generating: { label: 'Generating', theme: 'generating', icon: 'utility:sync', busy: true },
    Ready: { label: 'Ready', theme: 'ready', icon: 'utility:success', busy: false },
    Issued: { label: 'Issued', theme: 'issued', icon: 'utility:send', busy: false },
    Failed: { label: 'Failed', theme: 'failed', icon: 'utility:error', busy: false }
};

const UNKNOWN = { label: 'Unknown', theme: 'queued', icon: 'utility:question', busy: false };

export default class StatementGenerationStatus extends LightningElement {
    @api recordId;

    cycle;
    error;
    liveUpdatesDown = false;

    subscription;
    wiredResult;

    /**
     * Seeds the tile with whatever the cycle looks like on load. Every change after that arrives on the
     * event bus, so this wire is provisioned once rather than re-requested on a timer.
     */
    @wire(getCurrentCycle, { householdId: '$recordId' })
    handleCycle(result) {
        // Held so refreshApex can re-provision the same wire when an event says the data moved on.
        this.wiredResult = result;

        if (result.data !== undefined) {
            this.cycle = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = this.toMessage(result.error);
            this.cycle = undefined;
        }
    }

    connectedCallback() {
        // Without a subscription there is nothing to fall back on, so a dropped stream is surfaced
        // rather than swallowed - the tile says so and offers the manual refresh.
        onError(() => {
            this.liveUpdatesDown = true;
        });

        subscribe(STATUS_CHANNEL, -1, (message) => this.handleStatusEvent(message))
            .then((response) => {
                this.subscription = response;
                this.liveUpdatesDown = false;
            })
            .catch(() => {
                this.liveUpdatesDown = true;
            });
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }

    /**
     * The channel carries every household's transitions, so each message is filtered down to this
     * record before doing any work.
     *
     * The event deliberately doesn't carry the whole cycle. It says "this household moved", and the
     * component re-reads through the same wire, which keeps Apex the single source of truth for what
     * renders and avoids the payload and the query disagreeing.
     */
    handleStatusEvent(message) {
        const householdId = message?.data?.payload?.Household_Id__c;
        if (this.belongsToThisHousehold(householdId)) {
            refreshApex(this.wiredResult);
        }
    }

    belongsToThisHousehold(householdId) {
        if (!householdId || !this.recordId) {
            return false;
        }
        // Event payloads carry the 18-character Id; recordId may be the 15-character form.
        return householdId.substring(0, 15) === this.recordId.substring(0, 15);
    }

    // --- state ---------------------------------------------------------------------------------

    get presentation() {
        if (!this.cycle || !this.cycle.status) {
            return UNKNOWN;
        }
        return PRESENTATION[this.cycle.status] ?? UNKNOWN;
    }

    get hasCycle() {
        return !!this.cycle;
    }

    get showEmptyState() {
        return !this.error && this.cycle === null;
    }

    get isLoading() {
        return !this.error && this.cycle === undefined;
    }

    get badgeClass() {
        return `status-badge status-badge_${this.presentation.theme}`;
    }

    get iconClass() {
        return this.presentation.busy ? 'status-icon status-icon_spinning' : 'status-icon';
    }

    get isFailed() {
        return this.cycle?.status === 'Failed';
    }

    get hasDocument() {
        return !!this.cycle?.documentUrl;
    }

    get hasRetries() {
        return (this.cycle?.retryCount ?? 0) > 0;
    }

    get retryText() {
        const count = this.cycle?.retryCount ?? 0;
        return `${count} failed ${count === 1 ? 'attempt' : 'attempts'} so far`;
    }

    get accountText() {
        const count = this.cycle?.accountCount ?? 0;
        return `${count} ${count === 1 ? 'account' : 'accounts'}`;
    }

    // --- actions -------------------------------------------------------------------------------

    handleRefresh() {
        if (this.wiredResult) {
            refreshApex(this.wiredResult);
        }
    }

    // --- helpers -------------------------------------------------------------------------------

    toMessage(error) {
        return error?.body?.message ?? error?.message ?? 'Could not load statement status.';
    }
}