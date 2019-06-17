/// <amd-module name='main'/>

import Vue from "vue";

import 'confirmable-action';
import 'controlled-records';
import 'conversation';
import 'current-location-selector';
import 'file-issue-form';
import 'file-issue-notifications';
import 'file-uploader';
import 'linker';
import 'representation-linker';
import 'select-with-other-option';
import 'transfer-proposal-series';
import 'users-search';
import 'locations-search';
import 'transfer-sorter';
import 'file-issue-sorter';

declare var M: any; // Materialize on the window context

document.querySelectorAll('.vue-enabled').forEach(function(elt: Element) {
    /* tslint:disable:no-unused-expression */
    new Vue({el: elt});
});

M.ScrollSpy.init(document.querySelectorAll('.scrollspy'));
M.Dropdown.init(document.querySelectorAll('#userMenuTrigger'), {constrainWidth: false, coverTrigger: false});
