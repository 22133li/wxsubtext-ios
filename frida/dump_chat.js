/*
 * 微信 8.0.78 聊天界面结构 dump 脚本
 * 用法（手机上）：
 *   frida -U -f com.tencent.xin -l dump_chat.js
 * 然后在手机微信里打开任意一个单聊窗口，等几秒，把输出贴回来。
 */
function log(s) { console.log("[WXDUMP] " + s); }

function dumpClasses() {
    var chatClasses = [];
    ObjC.enumerateClasses({
        onMatch: function (name) {
            var low = name.toLowerCase();
            if (low.indexOf("chat") !== -1 || low.indexOf("chatting") !== -1) chatClasses.push(name);
        },
        onComplete: function () {}
    });
    log("含 chat 的类共 " + chatClasses.length + " 个：");
    chatClasses.slice(0, 60).forEach(function (c) { log("  class: " + c); });
}

function viewTree(v, depth, maxDepth) {
    if (depth > maxDepth || !v) return;
    var cls = v.$className || "?";
    var txt = "";
    try {
        if (v.isKindOfClass_(ObjC.classes.UILabel)) txt = ' text="' + (v.text() ? v.text().toString().slice(0, 40) : "") + '"';
    } catch (e) {}
    var f = v.frame ? (" frame=" + v.frame().size.width.toFixed(0) + "x" + v.frame().size.height.toFixed(0)
        + "@" + v.frame().origin.x.toFixed(0) + "," + v.frame().origin.y.toFixed(0)) : "";
    log(new Array(depth + 1).join("  ") + cls + f + txt);
    try {
        var subs = v.subviews();
        for (var i = 0; i < subs.count(); i++) viewTree(subs.objectAtIndex_(i), depth + 1, maxDepth);
    } catch (e) {}
}

function dumpChat() {
    var app = ObjC.classes.UIApplication.sharedApplication();
    var win = app.keyWindow();
    if (!win) { log("keyWindow 为空"); return; }
    // 找顶层 VC
    var vc = win.rootViewController();
    while (vc.presentedViewController && vc.presentedViewController()) vc = vc.presentedViewController();
    // 找 nav 栈顶
    try {
        var nav = vc;
        while (nav) {
            if (nav.isKindOfClass_(ObjC.classes.UINavigationController)) { vc = nav.topViewController(); break; }
            var child = nav.childViewControllers ? nav.childViewControllers() : null;
            if (child && child.count() > 0) nav = child.lastObject(); else break;
        }
    } catch (e) {}
    log("顶层 VC: " + vc.$className + " title=" + (vc.navigationItem().title() || vc.title() || ""));
    // 找 table/collection
    function findScroll(v) {
        if (v.isKindOfClass_(ObjC.classes.UITableView) || v.isKindOfClass_(ObjC.classes.UICollectionView)) return v;
        var subs = v.subviews();
        for (var i = 0; i < subs.count(); i++) { var r = findScroll(subs.objectAtIndex_(i)); if (r) return r; }
        return null;
    }
    var sv = findScroll(vc.view());
    if (!sv) { log("没找到列表视图"); return; }
    log("列表视图: " + sv.$className);
    var cells = sv.isKindOfClass_(ObjC.classes.UITableView) ? sv.visibleCells() : sv.visibleCells();
    log("可见 cell 数: " + cells.count());
    for (var i = 0; i < Math.min(cells.count(), 3); i++) {
        var cell = cells.objectAtIndex_(i);
        log("--- cell[" + i + "]: " + cell.$className + " ---");
        var content = cell.contentView ? cell.contentView() : cell;
        viewTree(content, 0, 4);
    }
}

setTimeout(function () {
    try {
        log("===== 类枚举 =====");
        dumpClasses();
        log("===== 当前界面 dump（请先打开一个单聊窗口）=====");
        dumpChat();
        log("每 15 秒重新 dump 一次，Ctrl+C 退出");
        setInterval(function () { try { dumpChat(); } catch (e) {} }, 15000);
    } catch (e) { log("异常: " + e); }
}, 2000);
