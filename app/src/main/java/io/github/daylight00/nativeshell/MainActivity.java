package io.github.daylight00.nativeshell;

import android.app.Activity;
import android.os.Bundle;
import android.view.Window;
import android.view.WindowManager;

public final class MainActivity extends Activity {
    private TerminalView terminalView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Window window = getWindow();
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        terminalView = new TerminalView(this);
        setContentView(terminalView);
    }

    @Override
    protected void onDestroy() {
        if (terminalView != null) {
            terminalView.close();
        }
        super.onDestroy();
    }
}
