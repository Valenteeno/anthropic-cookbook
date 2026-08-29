package com.factwarehouse.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.factwarehouse.app.ui.AppRoot
import com.factwarehouse.app.ui.theme.FactWarehouseTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            FactWarehouseTheme {
                AppRoot()
            }
        }
    }
}
