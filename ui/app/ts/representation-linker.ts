/// <amd-module name='representation-linker'/>


import Vue from "vue";
import VueResource from "vue-resource";
import Utils from "./utils";
// import Utils from "./utils";
// import UI from "./ui";
Vue.use(VueResource);
// import Utils from "./utils";
// import UI from "./ui";

interface Representation {
    id: string,
    label: string,
}

export default class RepresentationRequest {
    public static fromRepresentation(rep: Representation): RepresentationRequest {
        return new RepresentationRequest(rep.id, rep.label, 'DIGITAL');
    }
    
    constructor(public id: string,
                public label: string,
                public request_type: string) {
    }
}

Vue.component('representation-typeahead', {
    template: `
<div>
  <input id="representation-typeahead" v-on:keyup="handleInput" type="text" v-model="text" ref="text" placeholder="Search for records..."/>
  <ul>
    <li v-for="representation in matches">
      <a href="javascript:void(0);" v-on:click="select(representation)">{{ representation.label }}</a>
    </li>
  </ul>
</div>
`,
    data: function(): {matches: Representation[], text: string, handleInputTimeout:number|null} {
        return {
            matches: [],
            text: '',
            handleInputTimeout: null,
        };
    },
    methods: {
        handleInput() {
            if (this.text.length > 0) {
                if (this.handleInputTimeout != null) {
                    clearTimeout(this.handleInputTimeout);
                }
                this.handleInputTimeout = setTimeout(() => {
                    this.$http.get('/search/representations', {
                        method: 'GET',
                        params: {
                            q: this.text,
                        },
                    }).then((response: any) => {
                        return response.json();
                    }, () => {
                        this.matches = [];
                    }).then((json: any) => {
                        this.matches = json;
                    });
                }, 300);
            }
        },
        select(representation: Representation) {
            this.$emit('selected', representation);
            this.matches = [];
            this.text = '';
            (this.$refs.text as HTMLElement).focus();
        },
    },
});

Vue.component('representation-linker', {
    template: `
<div>
    <representation-typeahead v-on:selected="addSelected"></representation-typeahead>
    <table class="representation-linker-table">
        <thead>
            <tr>
                <th>Series ID</th>
                <th>Record ID</th>
                <th>Title</th>
                <th>Start Date</th>
                <th>End Date</th>
                <th>Representation ID</th>
                <th>Agency Assigned ID</th>
                <th>Previous System ID</th>
                <th>Format</th>
                <th>File Issue Allowed</th>
                <th>Intended Use</th>
                <th>Other Restrictions</th>
                <th>Processing/ Handling Notes</th>
                <th width="120px">Request Type</th>
                <th></th>
            </tr>
        </thead>
        <tbody>
            <tr v-for="representation in selected">
                <td>
                    <!-- series id -->
                    <input type="hidden" :name="buildPath('record_uri')" v-bind:value="representation.id"/>
                    <input type="hidden" :name="buildPath('record_label')" v-bind:value="representation.label"/>
                </td>
                <td><!-- record id --></td>
                <td><!-- title -->{{representation.label}}</td>
                <td><!-- start date --></td>
                <td><!-- end date --></td>
                <td><!-- representation id-->{{representation.id}}</td>
                <td><!-- agency assigned id--></td>
                <td><!-- previous system id--></td>
                <td><!-- format--></td>
                <td><!-- file issue allowed--></td>
                <td><!-- intended use--></td>
                <td><!-- other restrictions--></td>
                <td><!-- processing/handling notes --></td>
                <td>
                  <select class="browser-default" :name="buildPath('request_type')" v-model="representation.request_type" v-on:change="handleRequestTypeChange()">
                    <option value="DIGITAL">Digital</option>
                    <option value="PHYSICAL">Physical</option>
                  </select>
                </td>
                <td>
                  <button class="btn" v-on:click="removeSelected(representation)">Remove</button>
                </td>
            </tr>
        </tbody>
  </table>
</div>
`,
    data: function(): {selected: RepresentationRequest[]} {
        const prepopulated: RepresentationRequest[] = [];

        JSON.parse(this.representations).forEach((representationBlob: any) => {
            const rep: RepresentationRequest = new RepresentationRequest(representationBlob.record_uri, "FIXME need to refetch", representationBlob.request_type);
            prepopulated.push(rep);
        });

        return {
            selected: prepopulated
        };
    },
    props: ['input_path', 'representations'],
    methods: {
        getSelected: function() {
            return this.selected;
        },
        addSelected: function(representation:RepresentationRequest) {
            const selectedRepresentation: RepresentationRequest = RepresentationRequest.fromRepresentation(representation);
            this.selected.push(selectedRepresentation);
            this.$emit('change');
        },
        removeSelected: function(representationToRemove:RepresentationRequest) {
            this.selected = Utils.filter(this.selected, (representation: RepresentationRequest) => {
                return !(representation.id === representationToRemove.id && representation.request_type === representationToRemove.request_type); 
            });
            this.$emit('change');
        },
        handleRequestTypeChange: function() {
            this.$emit('change');
        },
        buildPath(field: string) {
            return this.input_path + "[" + field + "]";
        },
    },
});