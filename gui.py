import tkinter as tk
from typing import Callable

_COLOR_NORMAL = '#000000'
_COLOR_SUCCESS = '#388E3C'
_COLOR_ERROR = '#d32f2f'

class StatusWindow:
    def __init__(self, hotkey_label: str, on_exit: Callable[[], None]):
        self._root = tk.Tk()
        self._root.title('TFS Paster')
        self._root.attributes('-topmost', True)
        self._root.resizable(False, False)
        self._root.protocol('WM_DELETE_WINDOW', on_exit)

        tk.Label(self._root, text='Hotkey:', font=('', 12, 'bold')).grid(
            row=0, column=0, sticky='w', padx=8, pady=(8, 2))
        tk.Label(self._root, text=hotkey_label, font=('', 12, 'bold'), fg=_COLOR_SUCCESS).grid(
            row=0, column=1, sticky='w', padx=4, pady=(8, 2))
        tk.Label(
            self._root,
            text='Use hotkey to paste HTML to TFS instead of Ctrl+V',
            fg='#555555',
        ).grid(row=1, column=0, columnspan=2, sticky='w', padx=8)
        tk.Label(self._root, text='Status:', font=('', 12, 'bold')).grid(
            row=2, column=0, sticky='w', padx=8, pady=(4, 8))
        self._status_var = tk.StringVar(value='Idle')
        self._status_label = tk.Label(self._root, textvariable=self._status_var, font=('', 12))
        self._status_label.grid(row=2, column=1, sticky='w', padx=4, pady=(4, 8))

        self._root.geometry('450x95')
        self._root.bind('<Button-3>', self._show_context_menu)
        self._menu = tk.Menu(self._root, tearoff=0)
        self._menu.add_command(label='Exit', command=on_exit)

    def _show_context_menu(self, event: tk.Event) -> None:
        self._menu.post(event.x_root, event.y_root)

    def normal_status(self, msg: str) -> None:
        self._root.after(0, lambda: (
            self._status_var.set(msg),
            self._status_label.config(fg=_COLOR_NORMAL),
        ))

    def success_status(self, msg: str) -> None:
        self._root.after(0, lambda: (
            self._status_var.set(msg),
            self._status_label.config(fg=_COLOR_SUCCESS),
        ))

    def error_status(self, msg: str) -> None:
        self._root.after(0, lambda: (
            self._status_var.set(msg),
            self._status_label.config(fg=_COLOR_ERROR),
        ))

    def run(self) -> None:
        self._root.mainloop()
