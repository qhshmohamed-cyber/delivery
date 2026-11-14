const fs=require('fs'),vm=require('vm'),assert=require('assert');
const h=fs.readFileSync(require('path').join(__dirname,'../index.html'),'utf8');
new vm.Script(h.split('<script>')[1].split('</script>')[0]);
for(const removed of ['openRoleHelp','openTrainingMode','trainingNext','data-training','TRAIN-001'])assert(!h.includes(removed));
for(const retained of ['dlv_set_my_driver_duty','openShiftHandover','dlv_record_delay_reason','no-referrer','noindex'])assert(h.includes(retained));
console.log('PASS removed training/help; duty, handover, reasons and privacy retained');
