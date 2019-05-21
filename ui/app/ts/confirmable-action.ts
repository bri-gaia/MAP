/// <amd-module name='confirmable-action'/>


import Vue from "vue";
import VueResource from "vue-resource";
// import Utils from "./utils";
// import UI from "./ui";
Vue.use(VueResource);
// import Utils from "./utils";
// import UI from "./ui";

declare var M: any; // Materialize on the window context

Vue.component('confirmable-action', {
    template: `
<span>
    <a :class="css" v-on:click="show()">{{label}}</a>
    <div ref="modal" class="modal">
        <div class="modal-content">
            <div ref="spinner" class="preloader-wrapper small active right hide">
                <div class="spinner-layer spinner-green-only">
                    <div class="circle-clipper left">
                        <div class="circle"></div>
                    </div>
                    <div class="gap-patch">
                        <div class="circle"></div>
                    </div>
                    <div class="circle-clipper right">
                        <div class="circle"></div>
                    </div>
                </div>
            </div>

            <p v-html="message"></p>
        </div>
        <div class="modal-footer">
            <a href="#!" class="modal-close waves-effect waves-green btn-flat">Close</a>
            <a href="#!" class="waves-effect waves-green btn-flat" v-on:click="confirm()">Confirm</a>
        </div>
    </div>
</span>
`,
    data: function(): {active: boolean} {
        return {
            active: false,
        };
    },
    props: ['action', 'css', 'label', 'message', 'csrf_token', 'target_form_id'],
    methods: {
        show: function() {
            const modal: any = M.Modal.init(this.$refs.modal, {
            });
            modal.open();
        },
        confirm() {
            if (this.active) {
                return;
            }

            this.active = true;

            if (this.action !== undefined) {
                (this.$refs.spinner as Element).classList.remove('hide');
                this.$http.post(this.action,
                    {authenticity_token: this.csrf_token},
                    {emulateJSON: true})
                    .then(() => {
                        location.reload();
                    });
            } else if (this.target_form_id !== undefined) {
                const formEl:HTMLElement|null = document.getElementById(this.target_form_id);
                if (formEl) {
                    (<HTMLFormElement>formEl).submit();
                }
            }
        },
    },
});
