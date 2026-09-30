/*
 * 设置页诊断脚本
 * 用法（微信已运行时）：frida -U -n WeChat -l check_settings.js
 * 或冷启动：frida -U -f com.tencent.xin -l check_settings.js
 * 跑起来后，在手机微信里打开「我 -> 设置」，把 [WXSET] 开头的输出贴回来。
 */
function log(s) { console.log("[WXSET] " + s); }

function checkLoaded() {
    var found = [];
    try {
        if (ObjC.classes.WXSubtextHook) found.push("WXSubtextHook");
        if (ObjC.classes.WXSubtextSettingsVC) found.push("WXSubtextSettingsVC");
        if (ObjC.classes.WXSubtextConfig) found.push("WXSubtextConfig");
    } catch (e) {}
    log("插件类已加载: " + (found.length ? found.join(",") : "无（dylib 没注入！）"));
}
setTimeout(checkLoaded, 4000);

function findTV(v) {
    if (v.isKindOfClass_(ObjC.classes.UITableView)) return v;
    var subs = v.subviews();
    for (var i = 0; i < subs.count(); i++) {
        var r = findTV(subs.objectAtIndex_(i));
        if (r) return r;
    }
    return null;
}

function dumpSettings(vc) {
    var tv = null;
    try { tv = findTV(vc.view()); } catch (e) {}
    if (!tv) { log("没找到 UITableView"); return; }
    var dsName = "?";
    try { dsName = tv.dataSource().$className; } catch (e) {}
    var cells = tv.visibleCells();
    log("tableView=" + tv.$className + " dataSource=" + dsName + " 可见cell数=" + cells.count());
    var n = Math.min(cells.count(), 10);
    for (var i = 0; i < n; i++) {
        var cell = cells.objectAtIndex_(i);
        var labels = [];
        (function walk(v) {
            try {
                if (v.isKindOfClass_(ObjC.classes.UILabel)) {
                    var t = v.text();
                    if (t && t.toString().length) labels.push(t.toString().slice(0, 24));
                }
                var ss = v.subviews();
                for (var j = 0; j < ss.count(); j++) walk(ss.objectAtIndex_(j));
            } catch (e) {}
        })(cell);
        var tl = "";
        try { var x = cell.textLabel().text(); if (x) tl = x.toString().slice(0, 24); } catch (e) {}
        log("cell" + i + " class=" + cell.$className + " textLabel=" + (tl || "nil") + " labels=[" + labels.join("|") + "]");
    }
}

var VC = ObjC.classes.UIViewController;
Interceptor.attach(VC["- viewDidAppear:"].implementation, {
    onEnter: function (args) {
        var vc = new ObjC.Object(args[0]);
        var title = "";
        try { title = (vc.navigationItem().title() || vc.title() || "").toString(); } catch (e) {}
        if (title === "设置") {
            log("进入设置页 VC=" + vc.$className);
            var ref = vc;
            setTimeout(function () { dumpSettings(ref); }, 1200);
        }
    }
});
log("监听中：请在微信里打开 我 -> 设置");
